# ============================================================================
# Gentleman Guardian Angel - Cache Functions (PowerShell)
# ============================================================================

$CACHE_DIR = Join-Path $env:USERPROFILE ".cache\gga"

function Get-FileHash256 {
    param([string]$FilePath)
    if (Test-Path $FilePath) {
        (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
    } else {
        ""
    }
}

function Get-StringHash256 {
    param([string]$String)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($String)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha256.ComputeHash($bytes)
    [System.BitConverter]::ToString($hash) -replace '-', ''
}

function Get-ProjectId {
    $gitRoot = git rev-parse --show-toplevel 2>$null
    if ($gitRoot) {
        Get-StringHash256 $gitRoot
    } else {
        ""
    }
}

function Get-MetadataHash {
    param([string]$RulesFile, [string[]]$ConfigFiles)

    $rulesHash = ""
    $configHashes = @()

    if (Test-Path $RulesFile) {
        $rulesHash = Get-FileHash256 $RulesFile
    }

    foreach ($configFile in $ConfigFiles) {
        if (Test-Path -Path $configFile -PathType Leaf) {
            $configHashes += Get-FileHash256 $configFile
        }
    }

    $configHashJoined = $configHashes -join ":"
    Get-StringHash256 "${rulesHash}:${configHashJoined}"
}

function Get-ProjectCacheDir {
    $projectId = Get-ProjectId
    if (-not $projectId) {
        return ""
    }
    return Join-Path $CACHE_DIR $projectId
}

function Initialize-Cache {
    param([string]$RulesFile, [string[]]$ConfigFiles)

    $cacheDir = Get-ProjectCacheDir
    if (-not $cacheDir) {
        return ""
    }

    $filesDir = Join-Path $cacheDir "files"
    if (-not (Test-Path $filesDir)) {
        New-Item -ItemType Directory -Path $filesDir -Force | Out-Null
    }

    $metadataHash = Get-MetadataHash $RulesFile $ConfigFiles
    Set-Content -Path (Join-Path $cacheDir "metadata") -Value $metadataHash

    return $cacheDir
}

function Test-Cache-Valid {
    param([string]$RulesFile, [string[]]$ConfigFiles)

    $cacheDir = Get-ProjectCacheDir
    if (-not $cacheDir -or -not (Test-Path $cacheDir)) {
        return $false
    }

    $metadataFile = Join-Path $cacheDir "metadata"
    if (-not (Test-Path $metadataFile)) {
        return $false
    }

    $storedHash = Get-Content $metadataFile -Raw
    $currentHash = Get-MetadataHash $RulesFile $ConfigFiles

    return $storedHash -eq $currentHash
}

function Invalidate-Cache {
    $cacheDir = Get-ProjectCacheDir
    if ($cacheDir -and (Test-Path $cacheDir)) {
        Remove-Item -Path $cacheDir -Recurse -Force
    }
}

function Test-FileCached {
    param([string]$File)

    $cacheDir = Get-ProjectCacheDir
    $filesDir = Join-Path $cacheDir "files"
    if (-not $cacheDir -or -not (Test-Path $filesDir)) {
        return $false
    }

    $fileHash = Get-FileHash256 $File
    if (-not $fileHash) {
        return $false
    }

    $cacheFile = Join-Path $filesDir $fileHash
    if (Test-Path $cacheFile) {
        $cachedStatus = Get-Content $cacheFile -Raw
        return $cachedStatus -eq "PASSED"
    }

    return $false
}

function Cache-FileResult {
    param([string]$File, [string]$Status)

    $cacheDir = Get-ProjectCacheDir
    if (-not $cacheDir) {
        return
    }

    $filesDir = Join-Path $cacheDir "files"
    if (-not (Test-Path $filesDir)) {
        New-Item -ItemType Directory -Path $filesDir -Force | Out-Null
    }

    $fileHash = Get-FileHash256 $File
    if ($fileHash) {
        $cacheFile = Join-Path $filesDir $fileHash
        Set-Content -Path $cacheFile -Value $Status
    }
}

function Cache-FilesPassed {
    param([string]$Files)

    $Files -split "`n" | ForEach-Object {
        $file = $_.Trim()
        if ($file) {
            Cache-FileResult -File $file -Status "PASSED"
        }
    }
}

function Filter-UncachedFiles {
    param([string]$Files)

    $uncached = @()
    $Files -split "`n" | ForEach-Object {
        $file = $_.Trim()
        if ($file -and -not (Test-FileCached $file)) {
            $uncached += $file
        }
    }
    $uncached -join "`n"
}

function Clear-All-Cache {
    if (Test-Path $CACHE_DIR) {
        Remove-Item -Path $CACHE_DIR -Recurse -Force
    }
}

function Clear-Project-Cache {
    Invalidate-Cache
}
