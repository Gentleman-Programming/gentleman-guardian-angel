#requires -Version 7
<#
.SYNOPSIS Unified cache module for health check scripts.
#>
# ponytail: unified cache module
param([string]$Action,[string]$Key,[string]$Section,[object]$Data,[int]$TtlSeconds=300)

$cacheDir = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) ".learnings"
$cacheFile = Join-Path $cacheDir "health-cache.json"

function Get-Cache {
    param([string]$Key,[int]$TtlSeconds)
    if (-not (Test-Path $cacheFile)) { return $null }
    try {
        $cache = Get-Content $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $entry = $cache.PSObject.Properties[$Key]
        if (-not $entry) { return $null }
        $entry = $entry.Value
        $ts = $entry.timestamp
        if ($ts -is [datetime]) { $cachedAt = $ts }
        else { $cachedAt = [datetime]::ParseExact($ts, "yyyy-MM-ddTHH:mm:ssZ", $null) }
        $age = [int]((Get-Date) - $cachedAt).TotalSeconds
        if ($age -lt $TtlSeconds) { return $entry.data }
        return $null
    } catch { Write-Debug "cache.get($Key): $($_.Exception.Message)"; return $null }
}

function Set-Cache {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Key,[object]$Data)
    if ($PSCmdlet.ShouldProcess($cacheFile, "Set cache key '$Key'")) {
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
        $cache = @{}
        if (Test-Path $cacheFile) {
            try {
                $raw = Get-Content $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($raw) { $raw.PSObject.Properties | ForEach-Object { $cache[$_.Name] = $_.Value } }
            } catch { Write-Debug "cache.set load: $($_.Exception.Message)" }
        }
        $cache[$Key] = @{ timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"); data = $Data }
        $cache | ConvertTo-Json -Depth 5 | Set-Content $cacheFile -Encoding UTF8
    }
}

function Clear-Cache {
    param([string]$Section)
    if (-not (Test-Path $cacheFile)) { return }
    try {
        $raw = Get-Content $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $cache = @{}
        if ($raw) { $raw.PSObject.Properties | ForEach-Object { $cache[$_.Name] = $_.Value } }
        if ($Section) { $cache.Remove($Section) }
        else { $cache = @{} }
        $cache | ConvertTo-Json -Depth 5 | Set-Content $cacheFile -Encoding UTF8
    } catch { Write-Debug "cache.clear($Section): $($_.Exception.Message)" }
}

switch ($Action) {
    'get' { Get-Cache -Key $Key -TtlSeconds $TtlSeconds }
    'set' { Set-Cache -Key $Key -Data $Data }
    'clear' { Clear-Cache -Section $Section }
}
