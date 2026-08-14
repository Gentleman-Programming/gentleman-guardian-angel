#requires -Version 5.1
<#
.SYNOPSIS
    Sync gentleman-agent-gh to global OpenCode config — PS 5.1 compatible.
.DESCRIPTION
    Creates skill junctions, copies missing scripts, syncs AGENTS.md + configs.
    Fully self-contained — no PS7-only lib dependencies, runs on PS 5.1.
.PARAMETER DryRun  Show what would be done without making changes.
#>
param([switch]$DryRun)

function Get-GlobalConfigDir {
    $base = if ($env:OS -eq 'Windows_NT') { $env:USERPROFILE } else { $HOME }
    return Join-Path (Join-Path $base ".config") "opencode"
}
function New-CrossPlatLink {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$Path, [string]$Target)
    if ($env:OS -eq 'Windows_NT') { if ($PSCmdlet.ShouldProcess($Target, "Create junction: $Path")) { New-Item -ItemType Junction -Path $Path -Target $Target -Force | Out-Null } }
    else { if ($PSCmdlet.ShouldProcess($Target, "Create symlink: $Path")) { New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force | Out-Null } }
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path "$PSScriptRoot\.." -ErrorAction Stop
$srcSkills = Join-Path $repoRoot ".agents\skills"
$srcScripts = Join-Path $repoRoot "scripts"
$dstSkills = Join-Path (Get-GlobalConfigDir) "skills"
$dstScripts = Join-Path (Get-GlobalConfigDir) "scripts"
$globalCfg = Get-GlobalConfigDir

function Sync-DirectoryFile { param([string]$SrcDir,[string]$DstDir,[switch]$IsDryRun,[ref]$Count)
    if (-not (Test-Path $DstDir)) { New-Item -ItemType Directory -Path $DstDir -Force | Out-Null }
    if (Test-Path $SrcDir -PathType Container) {
        foreach ($f in Get-ChildItem -Path $SrcDir -File) {
            $dst = Join-Path $DstDir $f.Name
            $needsCopy = -not (Test-Path $dst)
            if (-not $needsCopy) { try { $needsCopy = (Get-FileHash $f.FullName).Hash -ne (Get-FileHash $dst -EA SilentlyContinue).Hash } catch { $needsCopy = $true } }
            if ($needsCopy) { if (-not $IsDryRun) { Copy-Item -LiteralPath $f.FullName -Destination $dst -Force; $Count.Value++ } }
        }
    }
}

function Sync-SingleFile { param([string]$Src,[string]$Dst,[switch]$IsDryRun,[ref]$Count)
    if (-not (Test-Path $Src -PathType Leaf)) { return }
    $needsCopy = -not (Test-Path $Dst)
    if (-not $needsCopy) { try { $needsCopy = (Get-FileHash -Path $Src).Hash -ne (Get-FileHash -Path $Dst -EA SilentlyContinue).Hash } catch { $needsCopy = $true } }
    if ($needsCopy) { if (-not $IsDryRun) { Copy-Item -LiteralPath $Src -Destination $Dst -Force; $Count.Value++ } }
}

Write-Host "`n=== sync-global-ps5: Gentleman Agent ===" -ForegroundColor Cyan

# Step 1: Skill junctions
Write-Host "`n[1] Skill junctions" -ForegroundColor Cyan
if (-not (Test-Path $dstSkills)) { New-Item -ItemType Directory -Path $dstSkills -Force | Out-Null }
$skillsCreated = 0; $skillsTotal = 0
foreach ($skill in Get-ChildItem -Directory -Path $srcSkills) {
    $skillsTotal++; $link = Join-Path $dstSkills $skill.Name
    if (-not (Test-Path $link)) {
        if ($DryRun) { Write-Host "  [dry-run] junction: $($skill.Name)" -Fore Yellow } else { New-CrossPlatLink -Path $link -Target $skill.FullName; Write-Host "  [created] $($skill.Name)" -Fore Green }
        $skillsCreated++
    }
}
Write-Host "  Skills: $skillsCreated new of $skillsTotal total" -Fore Green

# Step 2: Scripts copy
Write-Host "`n[2] Scripts sync" -ForegroundColor Cyan
$scriptsCopied = 0; $scriptsTotal = 0
foreach ($script in Get-ChildItem -Path $srcScripts -File) {
    $scriptsTotal++; $dst = Join-Path $dstScripts $script.Name
    $needsCopy = -not (Test-Path $dst)
    if (-not $needsCopy) { try { $needsCopy = (Get-FileHash -Path $script.FullName).Hash -ne (Get-FileHash -Path $dst -EA SilentlyContinue).Hash } catch { $needsCopy = $true } }
    if ($needsCopy) { if ($DryRun) { Write-Host "  [dry-run] $($script.Name)" -Fore Yellow } else { Copy-Item -LiteralPath $script.FullName -Destination $dst -Force; Write-Host "  [copied] $($script.Name)" -Fore Green; $scriptsCopied++ } }
}
Write-Host "  Scripts: $scriptsCopied/$scriptsTotal" -Fore Green

# Step 3: Config files
Write-Host "`n[3] Config sync" -ForegroundColor Cyan
$configFiles = @("AGENTS.md","ANTI-PATTERN-CATALOG.md","SKILLS-INDEX.md","CYCLE.md","BITACORA.md","review-rules.jsonc","PROJECT-SCORE.md","skills-lock.json","opencode.json","opencode.jsonc")
$configCopied = 0
foreach ($cfgFile in $configFiles) { Sync-SingleFile -Src (Join-Path $repoRoot $cfgFile) -Dst (Join-Path $globalCfg $cfgFile) -IsDryRun:$DryRun -Count ([ref]$configCopied) }
Write-Host "  Config: $configCopied/$($configFiles.Count)" -Fore Green

# Steps 4-6: Commands, Prompts, Plugins (identical pattern)
$syncSections = @(@{Name="Commands";Dir="commands"},@{Name="Prompts";Dir="prompts"},@{Name="Plugins";Dir="plugins"})
$stepNum = 4; foreach ($sec in $syncSections) {
    Write-Host "`n[$stepNum] $($sec.Name) sync" -ForegroundColor Cyan
    $count = 0; Sync-DirectoryFile -SrcDir (Join-Path $repoRoot $sec.Dir) -DstDir (Join-Path $globalCfg $sec.Dir) -IsDryRun:$DryRun -Count ([ref]$count)
    Write-Host "  $($sec.Name): $count" -Fore Green; $stepNum++
}

# Step 7: Verify junctions
Write-Host "`n[7] Verification" -ForegroundColor Cyan
$broken = 0
Get-ChildItem $dstSkills -Directory -EA SilentlyContinue | ForEach-Object { $t = Get-Item $_.FullName -Force -EA SilentlyContinue; if ($t.Target -and -not (Test-Path $t.Target)) { Write-Host "  [broken] $($_.Name)" -Fore Red; $broken++ } }
if ($broken -eq 0) { Write-Host "  All junctions valid" -Fore Green } else { Write-Host "  $broken broken junctions!" -Fore Red }

# Summary
Write-Host "`n=== Summary ===" -Fore Cyan
Write-Host "  Skills: $skillsCreated new | Scripts: $scriptsCopied | Config: $configCopied | Status: OK" -Fore Green
