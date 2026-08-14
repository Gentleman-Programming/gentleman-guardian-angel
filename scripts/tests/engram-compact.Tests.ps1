#requires -Version 7

<#
.SYNOPSIS
    Tests for scripts/engram-compact.ps1 — uses a THROWAWAY temp DB,
    never the real ~/.engram/engram.db.
#>
BeforeAll {
    $script:script = Join-Path $PSScriptRoot '..\engram-compact.ps1'
    $script:testDir = Join-Path $env:TEMP "engram-compact-test-$PID"
    $script:dbPath = Join-Path $testDir 'test.db'
    $script:bakDir = Join-Path $testDir 'backups'
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null

    # seed a small sqlite db with duplicates (observations + prompts + stale mutations)
    $pySeed = @'
import sqlite3, sys, os
db = sys.argv[1]
if os.path.exists(db): os.remove(db)
conn = sqlite3.connect(db)
c = conn.cursor()
c.execute("CREATE TABLE observations (id INTEGER PRIMARY KEY, content TEXT, title TEXT, type TEXT)")
c.execute("CREATE TABLE user_prompts (id INTEGER PRIMARY KEY, content TEXT)")
c.execute("CREATE TABLE sync_mutations (seq INTEGER PRIMARY KEY, occurred_at TEXT, target_key TEXT, entity TEXT, entity_key TEXT, op TEXT, payload TEXT, source TEXT, acked_at TEXT, project TEXT)")
c.execute("CREATE TABLE memory_relations (id INTEGER PRIMARY KEY)")
c.execute("INSERT INTO observations (content, title, type) VALUES ('dup-content', 't1', 'bugfix')")
c.execute("INSERT INTO observations (content, title, type) VALUES ('dup-content', 't1', 'bugfix')")
c.execute("INSERT INTO observations (content, title, type) VALUES ('unique', 't2', 'discovery')")
c.execute("INSERT INTO user_prompts (content) VALUES ('prompt-dup')")
c.execute("INSERT INTO user_prompts (content) VALUES ('prompt-dup')")
c.execute("INSERT INTO user_prompts (content) VALUES ('prompt-uniq')")
# one mutation 40 days old, one fresh
c.execute("INSERT INTO sync_mutations (occurred_at, target_key, entity, entity_key, op, payload, source, acked_at, project) VALUES ('2026-06-20 10:00:00', 'k1', 'e1', 'ek1', 'upsert', '{}', 's1', NULL, 'p1')")
c.execute("INSERT INTO sync_mutations (occurred_at, target_key, entity, entity_key, op, payload, source, acked_at, project) VALUES ('2026-08-01 10:00:00', 'k2', 'e2', 'ek2', 'upsert', '{}', 's2', NULL, 'p2')")
conn.commit(); conn.close()
print("seeded")
'@
    $pySeedFile = Join-Path $env:TEMP "engram-compact-seed-$PID.py"
    [IO.File]::WriteAllText($pySeedFile, $pySeed, [Text.UTF8Encoding]::new($false))
    $null = & python $pySeedFile $script:dbPath
    Remove-Item -LiteralPath $pySeedFile -Force -ErrorAction SilentlyContinue
}

AfterAll {
    Remove-Item -LiteralPath $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'engram-compact.ps1 — dry-run is non-destructive' {
    It 'fails cleanly when DB does not exist' {
        $out = & $script:script -DbPath (Join-Path $script:testDir 'nope.db') -Quiet 2>$null
        $LASTEXITCODE | Should -Be 2
        ($out | ConvertFrom-Json).ok | Should -Be $false
    }

    It 'reports duplicates without deleting in dry-run' {
        $hashBefore = (Get-FileHash -LiteralPath $script:dbPath).Hash
        $out = & $script:script -DbPath $script:dbPath -BackupDir $script:bakDir -Quiet
        $LASTEXITCODE | Should -Be 0
        $r = $out | ConvertFrom-Json
        $r.mode | Should -Be 'dry-run'
        $r.dedupe_observations | Should -Be 1
        $r.dedupe_prompts | Should -Be 1
        $r.purge_mutations | Should -Be 1
        (Get-FileHash -LiteralPath $script:dbPath).Hash | Should -Be $hashBefore
    }
}

Describe 'engram-compact.ps1 — apply path' {
    It 'removes duplicates, exports stale mutations, creates backup' {
        $out = & $script:script -DbPath $script:dbPath -BackupDir $script:bakDir -Yes -Quiet
        $LASTEXITCODE | Should -Be 0
        $r = $out | ConvertFrom-Json
        $r.mode | Should -Be 'apply'
        $r.backup | Should -Not -BeNullOrEmpty
        (Test-Path -LiteralPath $r.backup) | Should -Be $true
        $r.dedupe_observations | Should -Be 1
        $r.dedupe_prompts | Should -Be 1
        $r.purge_mutations | Should -Be 1
        $r.purge_export | Should -Not -BeNullOrEmpty
        (Test-Path -LiteralPath $r.purge_export) | Should -Be $true
        $r.after.observations | Should -Be 2   # 3 - 1 dup
        $r.after.prompts | Should -Be 2        # 3 - 1 dup
        $r.after.mutations | Should -Be 1      # 2 - 1 stale
    }
}

Describe 'engram-compact.ps1 — DB without user_prompts table' {
    BeforeAll {
        # seed a DB that predates the user_prompts schema (missing table)
        $script:legacyDb = Join-Path $script:testDir 'legacy.db'
        $pyLegacy = @'
import sqlite3, sys, os
db = sys.argv[1]
if os.path.exists(db): os.remove(db)
conn = sqlite3.connect(db)
c = conn.cursor()
c.execute("CREATE TABLE observations (id INTEGER PRIMARY KEY, content TEXT, title TEXT, type TEXT)")
c.execute("CREATE TABLE sync_mutations (seq INTEGER PRIMARY KEY, occurred_at TEXT, target_key TEXT, entity TEXT, entity_key TEXT, op TEXT, payload TEXT, source TEXT, acked_at TEXT, project TEXT)")
c.execute("INSERT INTO observations (content, title, type) VALUES ('legacy', 't1', 'discovery')")
conn.commit(); conn.close()
print("seeded")
'@
        $pyLegacyFile = Join-Path $env:TEMP "engram-compact-legacy-$PID.py"
        [IO.File]::WriteAllText($pyLegacyFile, $pyLegacy, [Text.UTF8Encoding]::new($false))
        $null = & python $pyLegacyFile $script:legacyDb
        Remove-Item -LiteralPath $pyLegacyFile -Force -ErrorAction SilentlyContinue
    }

    It 'succeeds in dry-run instead of crashing on missing table' {
        $out = & $script:script -DbPath $script:legacyDb -BackupDir $script:bakDir -Quiet
        $LASTEXITCODE | Should -Be 0
        $r = $out | ConvertFrom-Json
        $r.ok | Should -Be $true
        $r.mode | Should -Be 'dry-run'
        $r.before.prompts | Should -Be 0   # missing table counts as 0
        $r.dedupe_prompts | Should -Be 0   # no crash, nothing to dedupe
        $r.dedupe_observations | Should -Be 0
    }

    It 'succeeds in apply and still vacuums' {
        $out = & $script:script -DbPath $script:legacyDb -BackupDir $script:bakDir -Yes -Vacuum -Quiet
        $LASTEXITCODE | Should -Be 0
        $r = $out | ConvertFrom-Json
        $r.mode | Should -Be 'apply'
        $r.ok | Should -Be $true
        $r.after.prompts | Should -Be 0
        $r.after.observations | Should -Be 1
        $r.vacuum | Should -Be $true
    }
}

