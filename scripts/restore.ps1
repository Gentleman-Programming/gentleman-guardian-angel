#requires -Version 7


<#
.SYNOPSIS
Restore OpenCode config from git backup.
.DESCRIPTION
Lists snapshots or restores to a specific revision. Supports dry-run mode.
.PARAMETER Revision
Target revision (commit hash, HEAD~N, 'last' for HEAD~1). Empty = interactive.
.PARAMETER List
List snapshots only, no restore.
.PARAMETER DryRun
Show what would be restored without applying.
#>
Set-StrictMode -Version Latest
param([switch]$Quiet,[string]$Revision="",[switch]$List,[switch]$DryRun,[switch]$Force)
$ErrorActionPreference='Stop'
. (Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1")
$cfg=Join-Path (Get-GlobalConfigDir)
if(-not(Test-Path "$cfg\.git")){Write-Host "[err] No backup repo" -ForegroundColor Red;exit 1}
Push-Location $cfg;try{
    $c=git rev-list --count HEAD 2>$null
    if($List-or[string]::IsNullOrWhiteSpace($Revision)){
        Write-Host "=== Snapshots ($c) ===" -ForegroundColor Cyan
        git log --oneline --decorate -20 2>$null
        if($c-gt20){Write-Host "... ($($c-20) older)" -ForegroundColor Gray};if($List){return}
    }
    if([string]::IsNullOrWhiteSpace($Revision)){$Revision=Read-Host "Enter revision (or 'q')";if($Revision-eq'q'){return}}
    if($Revision-eq'last'){$Revision='HEAD~1'}
    # ponytail: git ref safety — reject shell metacharacters, only allow git-safe refs
    if($Revision -notmatch '^[\w/\.\-\^~@]+$'){Write-Host "[err] Invalid revision: contains unsafe characters" -ForegroundColor Red;exit 1}
    $resolved=git rev-parse --verify "${Revision}^{commit}" 2>$null
    if(-not$resolved){Write-Host "[err] Unknown: $Revision" -ForegroundColor Red;exit 1}
    # Use resolved hash for all subsequent commands to prevent injection via ref name
    $changed=git diff --name-only "$resolved" HEAD 2>$null
    if($changed){Write-Host "Files:" -ForegroundColor Blue;$changed|ForEach-Object{Write-Host "  $_"}}else{Write-Host "[warn] No file changes" -ForegroundColor Yellow}
    if($DryRun){Write-Host "[dry-run] Would restore to $Revision" -ForegroundColor Yellow;return}
    $confirm=Read-Host "Restore to $Revision? [y/N]"
    if($confirm-notmatch'^[yY]'){Write-Host "Cancelled.";return}
    git checkout "$resolved" -- . 2>$null
    if($?){Write-Host "[ok] Restored" -ForegroundColor Green}else{Write-Host "[err] Failed" -ForegroundColor Red}
}finally{Pop-Location}

