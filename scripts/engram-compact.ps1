#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Compact the Engram memory DB without losing information: backup, dedupe, purge stale sync mutations, VACUUM.

.DESCRIPTION
  Optimizes ~/.engram/engram.db:
    1. Backup  - copies DB (+ WAL/SHM if present) to a timestamped file in the backup dir.
    2. Dedupe  - removes exact-duplicate observations and user_prompts (keeps the newest row).
    3. Purge   - exports and removes sync_mutations older than -PurgeSyncOlderThanDays (default 30).
    4. VACUUM  - reclaims space after deletions.
  DRY-RUN BY DEFAULT: with no -Yes, prints exactly what would change without modifying anything.

.PARAMETER DbPath
  Path to the engram database. Default: $env:USERPROFILE\.engram\engram.db

.PARAMETER BackupDir
  Directory for backups and exports. Default: $env:USERPROFILE\.engram\backups

.PARAMETER DryRun
  Show what would change without modifying. This is the default when -Yes is absent.

.PARAMETER Force
  Apply the changes. Alias: -Yes (kept for backward compatibility). Without it the script only reports.

.PARAMETER PurgeSyncOlderThanDays
  Export + delete sync_mutations older than this many days. 0 = skip purge entirely.

.PARAMETER Vacuum
  Force VACUUM even if nothing was deleted.

.PARAMETER Quiet
  JSON-only output.

.EXAMPLE
  & scripts/engram-compact.ps1                       # dry-run report
  & scripts/engram-compact.ps1 -Force                # backup + dedupe + purge(30d) + vacuum
#>
param(
  [string]$DbPath = (Join-Path $env:USERPROFILE ".engram\engram.db"),
  [string]$BackupDir = (Join-Path $env:USERPROFILE ".engram\backups"),
  [switch]$DryRun,
  [Alias('Yes')]
  [switch]$Force,
  [int]$PurgeSyncOlderThanDays = 30,
  [switch]$Vacuum,
  [switch]$Quiet
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$apply = $Force -and (-not $DryRun)

if (-not (Test-Path -LiteralPath $DbPath)) {
  if ($Quiet) { Write-Output (@{ ok = $false; error = "DB not found: $DbPath" } | ConvertTo-Json -Compress) }
  else { Write-Error "DB not found: $DbPath" }
  exit 2
}

$dbInfo = Get-Item -LiteralPath $DbPath
if (-not $apply) { $action = "DRY-RUN (report only, nothing modified)" }
else { $action = "APPLY (backup + changes)" }
if (-not $Quiet) { Write-Output "== engram-compact | mode: $action | db: $($dbInfo.Length) bytes ==" }

# ---- 1. Backup ----
$backupFile = $null
if ($apply) {
  New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $backupFile = Join-Path $BackupDir "engram-$stamp.db"
  Copy-Item -LiteralPath $DbPath -Destination $backupFile
  foreach ($ext in @('.db-wal', '.db-shm')) {
    $side = "$DbPath$ext"
    if (Test-Path -LiteralPath $side) { Copy-Item -LiteralPath $side -Destination "$backupFile$ext" -Force }
  }
  if (-not $Quiet) { Write-Output "Backup: $backupFile" }
}

# ---- 2-4. Dedupe / purge / vacuum via Python (stdlib sqlite3) ----
$py = @'
import sqlite3, os, sys, csv, json, datetime

db = sys.argv[1]
purge_days = int(sys.argv[2])
apply = sys.argv[3] == "1"
backup_dir = sys.argv[4]

conn = sqlite3.connect(db, timeout=30)
conn.execute("PRAGMA busy_timeout=30000")
cur = conn.cursor()
force_vacuum = sys.argv[5] == "1"

def has_table(t):
    return cur.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (t,)).fetchone() is not None

def count(t):
    if not has_table(t):
        return 0
    return cur.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]

def dup_rows(t, cols):
    if not has_table(t):
        return []
    q = f"SELECT {cols} FROM {t} WHERE {cols} IN (SELECT {cols} FROM {t} GROUP BY {cols} HAVING COUNT(*) > 1)"
    return cur.execute(q).fetchall()

report = {
    "before": {"observations": count("observations"), "prompts": count("user_prompts"),
               "mutations": count("sync_mutations"), "size": os.path.getsize(db)},
    "dedupe_observations": 0, "dedupe_prompts": 0,
    "purge_mutations": 0, "purge_export": None,
    "after": None, "vacuum": False, "vacuum_error": None,
}

# dedupe observations: keep newest (max id), remove older exact-content copies
obs_dups = dup_rows("observations", "content")
if obs_dups:
    contents = list(dict.fromkeys(r[0] for r in obs_dups))
    ph = ",".join("?" * len(contents))
    q = (f"DELETE FROM observations WHERE content IN ({ph}) AND id NOT IN "
         f"(SELECT MAX(id) FROM observations WHERE content IN ({ph}) GROUP BY content)")
    if apply:
        c2 = cur.execute(q, contents + contents)
        report["dedupe_observations"] = c2.rowcount
    else:
        total = 0
        for c in contents:
            total += cur.execute("SELECT COUNT(*) FROM observations WHERE content = ? AND id NOT IN (SELECT MAX(id) FROM observations WHERE content = ?)", (c, c)).fetchone()[0]
        report["dedupe_observations"] = total

# dedupe prompts: keep newest (max id)
p_dups = dup_rows("user_prompts", "content")
if p_dups:
    contents = list(dict.fromkeys(r[0] for r in p_dups))
    ph = ",".join("?" * len(contents))
    q = (f"DELETE FROM user_prompts WHERE content IN ({ph}) AND id NOT IN "
         f"(SELECT MAX(id) FROM user_prompts WHERE content IN ({ph}) GROUP BY content)")
    if apply:
        c2 = cur.execute(q, contents + contents)
        report["dedupe_prompts"] = c2.rowcount
    else:
        total = 0
        for c in contents:
            total += cur.execute("SELECT COUNT(*) FROM user_prompts WHERE content = ? AND id NOT IN (SELECT MAX(id) FROM user_prompts WHERE content = ?)", (c, c)).fetchone()[0]
        report["dedupe_prompts"] = total

# purge sync_mutations older than N days: export first, then delete
if purge_days > 0 and has_table("sync_mutations"):
    cutoff = (datetime.datetime.now() - datetime.timedelta(days=purge_days)).strftime("%Y-%m-%d %H:%M:%S")
    cur.execute("SELECT COUNT(*) FROM sync_mutations WHERE occurred_at < ?", (cutoff,))
    n = cur.fetchone()[0]
    if n > 0:
        if apply:
            os.makedirs(backup_dir, exist_ok=True)
            exp = os.path.join(backup_dir, "sync_mutations_stale.csv")
            cur.execute("SELECT seq,target_key,entity,entity_key,op,payload,source,occurred_at,acked_at,project FROM sync_mutations WHERE occurred_at < ?", (cutoff,))
            rows = cur.fetchall()
            with open(exp, "w", newline="", encoding="utf-8") as f:
                w = csv.writer(f)
                w.writerow(["seq","target_key","entity","entity_key","op","payload","source","occurred_at","acked_at","project"])
                w.writerows(rows)
            cur.execute("DELETE FROM sync_mutations WHERE occurred_at < ?", (cutoff,))
            report["purge_mutations"] = n
            report["purge_export"] = exp
        else:
            report["purge_mutations"] = n

# vacuum: MUST run outside any transaction (implicit from DELETE/INSERT above),
# so use a separate connection AFTER commit. VACUUM inside a transaction fails silently.
if apply:
    conn.commit()
    report["after"] = {"observations": count("observations"), "prompts": count("user_prompts"),
                       "mutations": count("sync_mutations"), "size": os.path.getsize(db)}
    needs_vacuum = (report["dedupe_observations"] > 0 or report["dedupe_prompts"] > 0
                    or report["purge_mutations"] > 0 or purge_days == 0 or force_vacuum)
    if needs_vacuum:
        try:
            v = sqlite3.connect(db, timeout=30)
            v.execute("PRAGMA busy_timeout=30000")
            v.execute("VACUUM")
            v.close()
            report["vacuum"] = True
            report["after"] = {"observations": count("observations"), "prompts": count("user_prompts"),
                               "mutations": count("sync_mutations"), "size": os.path.getsize(db)}
        except sqlite3.OperationalError as e:
            report["vacuum_error"] = str(e)
            report["vacuum"] = False
else:
    report["vacuum"] = False
conn.close()
print(json.dumps(report))
'@

$pyFile = Join-Path $env:TEMP "engram-compact-$PID.py"
[IO.File]::WriteAllText($pyFile, $py, [Text.UTF8Encoding]::new($false))

try {
  $pyOut = & python $pyFile $DbPath $PurgeSyncOlderThanDays $(if ($apply) {'1'} else {'0'}) $BackupDir $(if ($Vacuum) {'1'} else {'0'}) 2>&1
  if ($LASTEXITCODE -ne 0) {
    if ($Quiet) { Write-Output (@{ ok = $false; error = ($pyOut -join ' ') } | ConvertTo-Json -Compress) }
    else { Write-Error "python failed: $($pyOut -join ' ')" }
    exit 3
  }
  $rep = $pyOut | Select-Object -Last 1 | ConvertFrom-Json
} finally {
  if (Test-Path -LiteralPath $pyFile) {
    try { Remove-Item -LiteralPath $pyFile -Force -ErrorAction Stop }
    catch { Write-Warning "engram-compact: could not clean temp file '$pyFile': $($_.Exception.Message)" }
  }
}

if ($Quiet) {
  $result = @{
    ok = $true
    mode = $(if ($apply) {'apply'} else {'dry-run'})
    backup = $backupFile
    before = $rep.before
    after = $rep.after
    dedupe_observations = $rep.dedupe_observations
    dedupe_prompts = $rep.dedupe_prompts
    purge_mutations = $rep.purge_mutations
    purge_export = $rep.purge_export
    vacuum = $rep.vacuum
    vacuum_error = $rep.vacuum_error
  }
  Write-Output ($result | ConvertTo-Json -Compress -Depth 4)
  exit 0
}

Write-Output ""
Write-Output "== Result =="
Write-Output ("Observations dup removed : {0}" -f $rep.dedupe_observations)
Write-Output ("Prompts dup removed     : {0}" -f $rep.dedupe_prompts)
Write-Output ("Sync mutations purged   : {0}" -f $rep.purge_mutations)
if ($rep.purge_export) { Write-Output ("  (exported to {0})" -f $rep.purge_export) }
if ($rep.vacuum_error) { Write-Warning "VACUUM skipped: $($rep.vacuum_error)" }
Write-Output ""
Write-Output ("Before: obs={0} prompts={1} mutations={2} size={3} bytes" -f $rep.before.observations, $rep.before.prompts, $rep.before.mutations, $rep.before.size)
if ($rep.after) {
  $saved = $rep.before.size - $rep.after.size
  Write-Output ("After:  obs={0} prompts={1} mutations={2} size={3} bytes  ({4} bytes saved)" -f $rep.after.observations, $rep.after.prompts, $rep.after.mutations, $rep.after.size, $saved)
} else {
  Write-Output "After:  (dry-run - nothing modified)"
}
Write-Output ""
Write-Output "Hint: run with -Yes to apply."
