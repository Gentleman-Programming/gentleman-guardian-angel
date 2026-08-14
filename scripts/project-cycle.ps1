#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  !pcycle orchestrator — run external project improvement cycle.
.DESCRIPTION
  Pipeline: detect -> profile -> resolve dimensions -> report -> .learnings log.
  Works on ANY project (Node, Go, Python, Rust, .NET, Ruby, PHP).
.PARAMETER Path  Target project root (default: cwd).
.PARAMETER Focus  Focus on specific dimension (e.g. "security").
.PARAMETER Migrate  Migration mode (--migrate npm_to_pnpm).
.PARAMETER N  Override number of sub-agents (default: auto from file count).
.PARAMETER AnalysisOnly  Generate report only, skip .learnings entry.
.PARAMETER Quiet  Output JSON only.
#>
param([string]$Path="",[string]$Focus="",[string]$Migrate="",[int]$N=0,[switch]$AnalysisOnly,[switch]$Quiet)
Set-StrictMode -Version Latest;$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent

if($Path-eq"--help"-or$Path-eq"-h"){Get-Help $MyInvocation.MyCommand.Path -Detailed;exit 0}
if(-not$Path){$Path=(Get-Location).Path}
Write-Host "[!pcycle] Project: $Path" -ForegroundColor Cyan

# 1. Profile
$ppScript=Join-Path $PSScriptRoot "project-profile.ps1"
if(-not(Test-Path $ppScript)){Write-Host "[!pcycle] ERROR: project-profile.ps1 not found" -Fore Red;exit 1}
$ppJson=& $ppScript -Path $Path -Quiet 2>$null
if(-not$ppJson){Write-Host "[!pcycle] ERROR: could not profile project" -Fore Red;exit 1}
try{$pp=$ppJson|ConvertFrom-Json}catch{Write-Host "[!pcycle] ERROR: invalid profile" -Fore Red;exit 1}

# 2. Resolve dimensions
$configPath=Join-Path $PSScriptRoot "cycle-config.jsonc";$dims=@()
if(Test-Path $configPath){
    $cfgRaw=(Get-Content $configPath -Raw) -replace '//.*?(?=\r?\n|$)','' -replace '/\*.*?\*/','' -replace '(?m)^\s*$',''
    try{
        $cfg=$cfgRaw|ConvertFrom-Json;$stack=$pp.stack.type;$allDims=$cfg.dimensions
        if($Migrate-ne""){$focus=$Migrate;$hasMig=$false;foreach($d in $allDims){if($d.id-eq"migration_readiness"){$hasMig=$true;break}};if($hasMig){$dims=@($allDims|Where-Object{$_.id-eq"migration_readiness"});$sec=$allDims|Where-Object{$_.id-eq"security"};if($sec){$dims=@($dims)+@($sec)};Write-Host "[!pcycle] Mode: migration ($Migrate)" -Fore Magenta}}
        elseif($Focus-ne""){$dims=@($allDims|Where-Object{$_.id-eq$Focus});if($dims.Count-eq 0){Write-Host "[!pcycle] WARNING: dimension '$Focus' not found" -Fore Yellow}}
        if($dims.Count-eq 0){$defIds=$cfg.default_dimensions;$addIds=@();foreach($d in $allDims){if($d.id-in@("dependencies","testing","ci_cd")){$hasStack=($d.stacks.PSObject.Properties.Name -contains $stack);if($d.always-or$hasStack){$addIds+=$d.id}}};$selIds=@($defIds)+@($addIds)|Select-Object -Unique;$dims=@($allDims|Where-Object{$_.id-in$selIds})}
        if($N-le 0){$fc=[int]$pp.size.files;foreach($s in $cfg.n_subagent_scaling.by_files){$mx=[int]$s.max;if($mx-eq-1-or$fc-le$mx){$N=[int]$s.N;break}};if($N-le 0){$N=3}}
    }catch{Write-Host "[!pcycle] WARNING: config parse error" -Fore Yellow;if($N-le 0){$N=3}}
}else{if($N-le 0){$N=3}}

if($dims.Count-eq 0){$dims=@(New-Object PSObject -Property @{id="security";label="Security";subagent_prompt="Audit project security comprehensively."})}

# 3. Summary
$cycleId="PCYC-"+(Get-Date -Format "yyyyMMdd")+"-"+(Get-Random -Minimum 100 -Maximum 999)
$sLabel=$pp.stack.type;$pkgMgr=$pp.stack.pkgManager;$fc=$pp.size.files;$loc=$pp.size.loc

if(-not$Quiet){Write-Host "=== !pcycle $cycleId ===" -Fore Green;Write-Host "  Project: $($pp.profile.name)" -Fore White;Write-Host "  Stack: $sLabel / $pkgMgr" -Fore Yellow;Write-Host "  Size: $fc files / $loc LOC" -Fore Gray;Write-Host "  N: $N sub-agents" -Fore Cyan;Write-Host "  Dims: $($dims.Count)" -Fore Magenta;foreach($d in $dims){Write-Host "    - $($d.label)" -Fore DarkCyan}}

# 4. Report
$rpt=@();$rpt+="---";$rpt+="cycle_id: $cycleId";$rpt+="project: $($pp.profile.name)";$rpt+="type: external";$rpt+="stack: $sLabel";$rpt+="pkg_manager: $pkgMgr";if($Migrate-ne""){$rpt+="migration: $Migrate"};$rpt+="n_subagents: $N";$rpt+="status: analysis_only";$rpt+="date: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')";$rpt+="---";$rpt+=""
$rpt+="# Project Cycle: $($pp.profile.name)";$rpt+="";$rpt+="**Date**: $(Get-Date -Format 'yyyy-MM-dd')";$rpt+="**Stack**: $sLabel / $pkgMgr";$rpt+="**Size**: $fc files / $loc LOC";$rpt+="**N sub-agents**: $N";$rpt+="**Status**: Analysis complete";$rpt+=""
$rpt+="## Profile";$rpt+="";$rpt+="| Property | Value |";$rpt+="|----------|-------|";$rpt+="| Stack | $sLabel |";$rpt+="| Package Manager | $pkgMgr |";$rpt+="| Frameworks | $($pp.stack.frameworks -join ', ') |";$rpt+="| Test Runner | $($pp.stack.testRunner) |";$rpt+="| CI Provider | $($pp.stack.ciProvider) |";$rpt+="| Docker | $($pp.stack.hasDocker) |";$rpt+="| Files | $fc |";$rpt+="| LOC | $loc |";$rpt+="| Maturity | $($pp.size.maturity) |";$rpt+=""
$rpt+="## Analysis Dimensions";$rpt+=""
foreach($d in $dims){$rpt+="### $($d.label)";$rpt+="";$rpt+="**Prompt**: $($d.subagent_prompt)";$rpt+="";$hasStack=$null-ne($d.stacks.PSObject.Properties|Select-Object -First 1);if($hasStack-and($d.stacks.PSObject.Properties.Name -contains $sLabel)){$checks=$d.stacks.$sLabel.checks;if($checks){$rpt+="**Checks**:";foreach($c in $checks){$rpt+="- [ ] $c"};$rpt+=""}};if($Migrate-ne""-and$d.id-eq"migration_readiness"){$mc=$d.stacks.node.migrations.$Migrate;if($mc){$rpt+="**Migration checks**:";foreach($c in $mc.checks){$rpt+="- [ ] $c"};$rpt+=""}}}
$rpt+="## Recommendations";$rpt+="*(To be filled)*";$rpt+="## Next Steps";$rpt+="- Execute sub-agent analysis";$rpt+="- Merge findings";$rpt+="- Fill recommendations";$rpt+="- Run execution cycle";$rpt+=""

# 5. Save report
$cyclesDir=Join-Path $repoRoot "docs\cycles";if(-not(Test-Path $cyclesDir)){New-Item -ItemType Directory -Path $cyclesDir -Force | Out-Null}
$dateStr=(Get-Date).ToString("yyyyMMdd");$slug=$pp.profile.name -replace '[^a-zA-Z0-9-]','-';$fn="cycle-${slug}-${dateStr}.md";$reportPath=Join-Path $cyclesDir $fn
$rpt|Out-String|Set-Content -LiteralPath $reportPath -Encoding UTF8;Write-Host "[!pcycle] Report: $reportPath" -Fore Green

# 6. Learnings entry
if(-not$AnalysisOnly){$lDir=Join-Path $repoRoot ".learnings\cycles";if(-not(Test-Path $lDir)){New-Item -ItemType Directory -Path $lDir -Force | Out-Null};$lf="pcyc-${dateStr}-$($pp.profile.name -replace '[^a-zA-Z0-9-]','-').md";$lp=Join-Path $lDir $lf
    $le=@();$le+="---";$le+="type: project";$le+="cycle_id: $cycleId";$le+="date: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')";$le+="project: $($pp.profile.name)";$le+="stack: $sLabel";$le+="pkg_manager: $pkgMgr";if($Migrate-ne""){$le+="migration: $Migrate"};$le+="status: analysis_only";$le+="---";$le+=""
    $le+="## Learning Entry";$le+="### What";$le+="!pcycle analysis of $($pp.profile.name) ($sLabel/$pkgMgr, $fc files, $loc LOC)";$le+="### Decisions";$le+="- N: $N";$le+="- Dims: $($dims.Count) ($($dims.label -join ', '))";if($Migrate-ne""){$le+="- Migration: $Migrate"};$le+="### Cross-Ref";$le+="- Report: docs/cycles/$fn";$le+=""
    $le|Out-String|Set-Content -LiteralPath $lp -Encoding UTF8;Write-Host "[!pcycle] Learnings: $lp" -Fore Green}

# 7. Output
$r=[PSCustomObject]@{cycle_id=$cycleId;project=$pp.profile.name;stack=$sLabel;pkgManager=$pkgMgr;n_subagents=$N;dimensions=@($dims|ForEach-Object{$_.id});report=$reportPath;learnings=if(-not$AnalysisOnly){$lp}else{$null};status="analysis_only"}
if($Quiet){$r|ConvertTo-Json -Depth 3}else{Write-Host "`n[!pcycle] Done. N=$N, $($dims.Count) dimensions." -Fore Green}
exit 0
