#requires -Version 7
<#
.SYNOPSIS
  Pull-from-Upstream Workflow — detect, classify, and selectively apply upstream changes.
.DESCRIPTION
  Connects to the upstream repository and classifies changes as NEW (files only in upstream),
  MODIFIED (differ between upstream and local), or OURS ONLY (only local).
  Supports Check, Apply-New, and Apply-File modes.
.PARAMETER Mode
  Check (default): list differences. Apply-New: apply new skills/scripts from upstream.
  Apply-File: apply a specific file from upstream.
.PARAMETER TargetFile
  Path to target file (required for Apply-File mode).
.PARAMETER Branch
  Upstream branch to compare against (default: main).
.PARAMETER Remote
  Remote name (default: upstream).
.NOTES
  Excludes: setup-install.ps1, install.sh, README.md, .env.example (local customizations).
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$Quiet,
  [Parameter(Position = 0)]
  [ValidateSet('Check', 'Apply-New', 'Apply-File')]
  [string]$Mode = 'Check',
  [string]$TargetFile = '',
  [string]$Branch = 'main',
  [string]$Remote = 'upstream'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ponytail: files we customize locally — upstream must NOT overwrite
$excludeList = @('setup-install.ps1', 'install.sh', 'README.md', '.env.example')

# Mapping: upstream path → local path (with path translation)
$pathMappings = @(
  @{ UpstreamPath = 'skills/';        LocalPath = '.agents/skills/'; Label = 'Skills' }
  @{ UpstreamPath = 'scripts/';       LocalPath = 'scripts/';       Label = 'Scripts' }
  @{ UpstreamPath = '';               LocalPath = '';               Label = 'Root files' }
)

Push-Location (Resolve-Path "$PSScriptRoot/..")

try {
  # --- Helper: check if remote exists ---
  function Test-GitRemote([string]$Name) {
    (git remote) -contains $Name
  }

  # --- Helper: build hash table from git ls-tree ---
  function Get-FileHashTable([string]$GitRef, [string]$Dir) {
    $hashes = @{}
    if ([string]::IsNullOrEmpty($Dir)) {
      git ls-tree $GitRef | ForEach-Object {
        $parts = $_ -split '\s+'
        $hashes[$parts[3]] = $parts[2]
      }
    } else {
      git ls-tree -r $GitRef -- "$Dir" | ForEach-Object {
        $parts = $_ -split '\s+'
        $hashes[$parts[3]] = $parts[2]
      }
    }
    return $hashes
  }

  # --- Helper: convert local path to upstream path ---
  function Convert-LocalToUpstreamPath([string]$LocalPath) {
    $result = $LocalPath
    foreach ($mapping in $pathMappings) {
      if (-not [string]::IsNullOrEmpty($mapping.LocalPath) -and $LocalPath.StartsWith($mapping.LocalPath)) {
        $result = $LocalPath.Replace($mapping.LocalPath, $mapping.UpstreamPath)
        break
      }
    }
    return $result
  }

  # --- Validate remote ---
  if (-not (Test-GitRemote $Remote)) {
    Write-Warning "Remote '$Remote' not found"
    exit 1
  }

  # --- Fetch upstream ---
  if(-not $Quiet) { Write-Host "Fetch $Remote/$Branch..." }
  git fetch $Remote $Branch 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "Fetch failed"
    exit 1
  }

  $remoteRef = "$Remote/$Branch"
  $localRef = 'HEAD'

  # --- Count ahead/behind ---
  $behind = git rev-list --count "${localRef}..${remoteRef}" 2>&1
  $ahead  = git rev-list --count "${remoteRef}..${localRef}" 2>&1
  if(-not $Quiet) { Write-Host "Behind: $behind  Ahead: $ahead  Total: $([int]$behind + [int]$ahead)" }

  # --- Classify changes by category ---
  $allNew = @()
  $allMod = @()
  $allOurs = @()

  foreach ($mapping in $pathMappings) {
    $upstreamDir = $mapping.UpstreamPath
    $localDir    = $mapping.LocalPath
    $categoryLabel = $mapping.Label

    # List upstream files
    if ([string]::IsNullOrEmpty($upstreamDir)) {
      $upstreamFiles = @(git ls-tree -r --name-only $remoteRef |
        Where-Object { $_ -notmatch '^skills/|^scripts/|^\.' -and $_ -notlike '*/' })
    } else {
      $upstreamFiles = @(git ls-tree -r --name-only $remoteRef -- "$upstreamDir" |
        ForEach-Object {
          if (-not [string]::IsNullOrEmpty($localDir) -and $localDir -ne $upstreamDir) {
            $_.Replace($upstreamDir, $localDir)
          } else { $_ }
        })
    }

    # List local files in the same scope
    if ([string]::IsNullOrEmpty($localDir)) {
      $localFiles = @(git ls-tree -r --name-only $localRef |
        Where-Object { $_ -notmatch '^\.agents/skills/|^scripts/|^\.' -and $_ -notlike '*/' })
    } else {
      $localFiles = @(git ls-tree -r --name-only $localRef -- "$localDir" |
        ForEach-Object { $_ })
    }

    $uniqueUpstream = @($upstreamFiles | Sort-Object -Unique)
    $uniqueLocal    = @($localFiles | Sort-Object -Unique)

    # NEW: in upstream but not local
    $newItems = @($uniqueUpstream | Where-Object { $_ -notin $uniqueLocal })
    # OURS: in local but not upstream
    $oursItems = @($uniqueLocal | Where-Object { $_ -notin $uniqueUpstream })
    # Candidates for MOD: in both
    $commonItems = @($uniqueUpstream | Where-Object { $_ -in $uniqueLocal })

    # Filter exclusions — compare by leaf name (path-qualified items vs bare filenames)
    $newItems = $newItems | Where-Object { (Split-Path $_ -Leaf) -notin $excludeList }
    if ($categoryLabel -eq 'Root files') {
      $newItems = $newItems | Where-Object { $_ -notmatch '\.md$|LICENSE' }
    }

    # MODIFIED: in both but with different hashes
    $modifiedItems = @()
    if ($categoryLabel -ne 'Root files') {
      # Build upstream hash map
      $upstreamHashes = Get-FileHashTable -GitRef $remoteRef -Dir $upstreamDir
      if (-not [string]::IsNullOrEmpty($localDir) -and $localDir -ne $upstreamDir) {
        $new = @{}
        $upstreamHashes.Keys | ForEach-Object { $new[$_.Replace($upstreamDir, $localDir)] = $upstreamHashes[$_] }
        $upstreamHashes = $new
      }

      # Build local hash map
      $localHashes = Get-FileHashTable -GitRef $localRef -Dir $localDir

      # Compare hashes
      $commonItems | ForEach-Object {
        if ($upstreamHashes[$_] -and $localHashes[$_] -and $upstreamHashes[$_] -ne $localHashes[$_]) {
          $modifiedItems += $_
        }
      }
      $modifiedItems = $modifiedItems | Where-Object { (Split-Path $_ -Leaf) -notin $excludeList }
    }

    # --- Output per category ---
    if(-not $Quiet) {
      Write-Host "--- $categoryLabel ---"
      if ($newItems.Count)     { Write-Host "NEW $($newItems.Count)";     $newItems | ForEach-Object { Write-Host "  + $_" } }
      if ($modifiedItems.Count){ Write-Host "MOD $($modifiedItems.Count)";$modifiedItems | ForEach-Object { Write-Host "  ~ $_" } }
      if ($oursItems.Count)    { Write-Host "OURS $($oursItems.Count)";  $oursItems | ForEach-Object { Write-Host "  - $_" } }
      if (-not $newItems.Count -and -not $modifiedItems.Count -and -not $oursItems.Count) {
        Write-Host "(none)"
      }
    }

    $allNew += $newItems
    $allMod += $modifiedItems
    $allOurs += $oursItems
  }

  if(-not $Quiet) { Write-Host "New:$($allNew.Count) Mod:$($allMod.Count) Ours:$($allOurs.Count)" }

  # --- Apply-New mode ---
  if ($Mode -eq 'Apply-New') {
    $skillScriptItems = @($allNew | Where-Object {
      $_ -match '^\.agents/skills/' -or $_ -match '^scripts/'
    })
    $otherItems = @($allNew | Where-Object { $_ -notin $skillScriptItems })

    if ($otherItems.Count) {
      if(-not $Quiet) { Write-Host "Skip $($otherItems.Count) non-skill/script" }
    }

    if (-not $skillScriptItems.Count) {
      if(-not $Quiet) { Write-Host "No new skills/scripts" }
      exit 0
    }

    if(-not $Quiet) { Write-Host "Apply $($skillScriptItems.Count) files..." }
    $applied = 0
    $failed = 0

    foreach ($file in $skillScriptItems) {
      # Reverse-map: local path → upstream path
      $upstreamFile = Convert-LocalToUpstreamPath $file

      # Ensure parent directory exists
      $parentDir = Split-Path $file -Parent
      if (-not [string]::IsNullOrEmpty($parentDir) -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
      }

      if(-not $Quiet) { Write-Host "  + $file" }
      git checkout "$Remote/$Branch" -- "$upstreamFile" 2>&1 | Out-Null
      if ($LASTEXITCODE -eq 0) {
        if ($upstreamFile -ne $file) {
          if (Test-Path $upstreamFile) {
            Move-Item -Path $upstreamFile -Destination $file -Force
          }
        }
        $null = git add $file 2>&1
        $applied++
      } else {
        Write-Warning "FAILED $upstreamFile"
        $failed++
      }
    }

    if(-not $Quiet) { Write-Host "$applied applied, $failed failed" }
    if ($applied -and -not $Quiet) { Write-Host "Staged. Run git status then commit" }
  }

  # --- Apply-File mode ---
  if ($Mode -eq 'Apply-File') {
    if ([string]::IsNullOrEmpty($TargetFile)) {
      Write-Warning "Usage: -TargetFile path"
      exit 1
    }

    $fileName = Split-Path $TargetFile -Leaf
    if ($fileName -in $excludeList -or $TargetFile -in $excludeList) {
      Write-Warning "SKIP '$TargetFile' — excluded (local customization)"
      exit 0
    }

    # Reverse-map
    $upstreamFile = Convert-LocalToUpstreamPath $TargetFile

    if(-not $Quiet) { Write-Host "Checkout '$upstreamFile' from $Remote/$Branch..." }
    git checkout "$Remote/$Branch" -- "$upstreamFile" 2>&1

    if ($LASTEXITCODE -eq 0) {
      if ($upstreamFile -ne $TargetFile) {
        $parentDir = Split-Path $TargetFile -Parent
        if (-not [string]::IsNullOrEmpty($parentDir) -and -not (Test-Path $parentDir)) {
          New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        Move-Item -Path $upstreamFile -Destination $TargetFile -Force
      }
      if(-not $Quiet) { Write-Host "Done. Run git diff --cached $TargetFile" }
    } else {
      Write-Warning "Failed $upstreamFile"
    }
  }
} finally {
  Pop-Location
}
