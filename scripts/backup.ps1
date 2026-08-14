#requires -Version 7


<#
.SYNOPSIS
Backup OpenCode config to git repository.
.DESCRIPTION
Creates or updates a git backup of the OpenCode config directory.
.PARAMETER Message
Optional commit message for the backup.
.PARAMETER Force
Backup even if no changes detected.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
param([switch]$Quiet,[string]$Message="",[switch]$Force,[switch]$DryRun)
. (Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1")
$cfg=Join-Path (Get-GlobalConfigDir)
if(-not(Test-Path $cfg)){Write-Host "[err] $cfg not found" -ForegroundColor Red;exit 1}
Push-Location $cfg
try{
    if(-not(Test-Path "$cfg\.git")){
        Write-Host "[info] Initializing git repo at $cfg" -ForegroundColor Blue
        git init --quiet 2>&1 | Out-Null
        @"
scripts/
node_modules/
"@ | Set-Content -Path .gitignore -Encoding UTF8 -Force
        git add .gitignore 2>&1 | Out-Null
        git commit -m "init: backup repo" --quiet 2>&1 | Out-Null
    }
    git add -A 2>&1 | Out-Null
    $st=git status --porcelain 2>&1 | Out-String
    if([string]::IsNullOrWhiteSpace($st)-and-not$Force){Write-Host "[ok] No changes to backup." -ForegroundColor Green;return}
    $ts=Get-Date -Format "yyyy-MM-dd HH:mm"
    $msg=if([string]::IsNullOrWhiteSpace($Message)){"backup $ts"}else{"$Message ($ts)"}
    git commit -m $msg --quiet 2>&1 | Out-Null
    if($LASTEXITCODE-eq-0){Write-Host "[ok] Backup committed: $msg" -ForegroundColor Green}else{Write-Host "[warn] Nothing to commit" -ForegroundColor Yellow}
    $c=git rev-list --count HEAD 2>&1 | Out-String;$c=$c.Trim()
    $l=git log -1 --oneline 2>&1 | Out-String;$l=$l.Trim()
    Write-Host "[info] Snapshots: $c | Latest: $l" -ForegroundColor Blue
}finally{Pop-Location}

