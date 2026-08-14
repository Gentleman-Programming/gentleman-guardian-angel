#requires -Version 7.0
<#
.SYNOPSIS
    Shared file manifest for repo analysis scripts (pssa-gate, score-auto).
.DESCRIPTION
    Dot-sourced by analysis scripts. Exposes Get-FileManifest — a single
    inventory of analyzable files with content hashes, so consumers don't
    each walk the tree independently.
    Lazy hashing: SHA256 is computed only for files whose (length, mtime)
    changed since the last call; unchanged files reuse their previous hash
    from a persistent stamp cache (per-repo, in %TEMP%\opencode).
.NOTES
    This file is NOT meant to be invoked directly.
#>

function Get-FileManifest {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Alias('Root')]
        [string]$Path = (Get-Location).Path,
        [switch]$ForceHash
    )
    $root = (Resolve-Path $Path).Path

    $rxExclude = '(^|[\\/])(node_modules|experiments|skills)([\\/]|$)'
    $rxExt     = '\.(ps1|psm1)$'

    $scriptPaths = @(Get-ChildItem -LiteralPath $root -File -Recurse -EA SilentlyContinue |
        Where-Object { $_.FullName -notmatch $rxExclude -and $_.FullName -match $rxExt })

    $skillPaths = @(Get-ChildItem -LiteralPath (Join-Path $root '.agents\skills') -File -Filter 'SKILL.md' -Recurse -EA SilentlyContinue)

    # --- Lazy hash: load previous stamps from persistent per-repo cache ---
    $cacheDir  = Join-Path ([IO.Path]::GetTempPath()) 'opencode'
    $cacheFile = Join-Path $cacheDir "file-manifest-$([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($root))).Replace('-','').Substring(0,16)).json"
    $prevStamps = @{}
    if (-not $ForceHash -and (Test-Path $cacheFile)) {
        try {
            $cached = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
            # Guard: cache is per-repo (16-hex key collision) — never load a foreign repo's stamps
            if ($cached.root -eq $root) {
                foreach ($p in $cached.stamps.PSObject.Properties) { $prevStamps[$p.Name] = $p.Value }
            }
        } catch { $prevStamps = @{} }
    }

    $needHash = @()
    $manifest = @()
    foreach ($f in @($scriptPaths + $skillPaths)) {
        $rp = $f.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
        $grp = if ($rp -match '^\.agents/skills/') { 'skill' } else { 'script' }
        $s = $null
        if ($prevStamps.ContainsKey($rp)) { $s = $prevStamps[$rp] }
        $stampMatch = $null -ne $s -and [int64]$s.len -eq $f.Length -and [int64]$s.mtime -eq $f.LastWriteTimeUtc.Ticks
        if ($stampMatch -and -not $ForceHash) {
            # unchanged: reuse previous hash, no I/O on content
            $manifest += [PSCustomObject]@{ relpath = $rp; length = $f.Length; mtime = $f.LastWriteTimeUtc.Ticks; sha256 = [string]$s.sha256; group = $grp }
        } else {
            $needHash += $f.FullName
            $manifest += [PSCustomObject]@{ relpath = $rp; length = $f.Length; mtime = $f.LastWriteTimeUtc.Ticks; sha256 = ''; group = $grp }
        }
    }

    # --- Hash only the changed/new files, in parallel ---
    # NOTE: ForEach-Object -Parallel does NOT guarantee output order, so each
    # hash is bound to its own full path (path\tDigest) — never pair by index.
    if ($needHash.Count -gt 0) {
        $hashMap = @{}
        $needHash | ForEach-Object -Parallel {
            $fp = $_
            $h = [Security.Cryptography.SHA256]::Create()
            try {
                $digest = ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($fp)))).Replace('-', '').ToLower()
                "$fp`t$digest"
            } catch { "$fp`t" } finally { $h.Dispose() }
        } -ThrottleLimit 8 | ForEach-Object {
            $pair = $_ -split "`t", 2
            if ($pair.Count -eq 2 -and $pair[1]) {
                $rp = $pair[0].Substring($root.Length).TrimStart('\').Replace('\', '/')
                $hashMap[$rp] = $pair[1]
            }
        }
        foreach ($m in $manifest) { if (-not $m.sha256) { $m.sha256 = $hashMap[$m.relpath] } }
    }

    # --- Persist stamps for next call ---
    try {
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
        $stamps = @{}
        foreach ($m in $manifest) { $stamps[$m.relpath] = @{ len = $m.length; mtime = $m.mtime; sha256 = $m.sha256 } }
        @{ root = $root; generated = (Get-Date -Format 'o'); stamps = $stamps } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cacheFile -Encoding UTF8
    } catch { Write-Debug "file-manifest cache save: $($_.Exception.Message)" }

    @($manifest | Sort-Object relpath)
}
