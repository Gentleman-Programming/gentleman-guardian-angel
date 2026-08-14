#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]

<#
.SYNOPSIS
  Skill Validation Protocol — multi-trial benchmark vs baseline.
.DESCRIPTION
  Computes averages, deltas, and SkillsBench verdict for a skill under test.
  Metrics: tool_calls(lower=better), tokens(lower), score(higher), errors(lower), iterations(lower).
.PARAMETER SkillName
  Name of the skill being validated.
.PARAMETER BaselineToolCalls
.PARAMETER BaselineTokens
.PARAMETER BaselineScore
.PARAMETER BaselineErrors
.PARAMETER BaselineIterations
.PARAMETER TrialToolCalls
  Array of 3 values with skill, e.g. @(5,4,6).
.PARAMETER TrialTokens
.PARAMETER TrialScores
.PARAMETER TrialErrors
.PARAMETER TrialIterations
.PARAMETER OutputJson
  Switch: output JSON.
.EXAMPLE
  .\scripts\skill-validate.ps1 -SkillName "accessibility" -BaselineToolCalls 8 -BaselineTokens 1200 -BaselineScore 6.0 -BaselineErrors 2 -BaselineIterations 14 -TrialToolCalls @(5,6,4) -TrialTokens @(850,920,780) -TrialScores @(8.0,7.5,8.6) -TrialErrors @(1,0,0) -TrialIterations @(9,8,7)
#>
param(
    [switch]$Quiet,
  [Parameter(Mandatory=$true)][string]$SkillName,
  [Parameter(Mandatory=$true)][int]$BaselineToolCalls,
  [Parameter(Mandatory=$true)][int]$BaselineTokens,
  [Parameter(Mandatory=$true)][double]$BaselineScore,
  [Parameter(Mandatory=$true)][int]$BaselineErrors,
  [Parameter(Mandatory=$true)][int]$BaselineIterations,
  [Parameter(Mandatory=$true)][int[]]$TrialToolCalls,
  [Parameter(Mandatory=$true)][int[]]$TrialTokens,
  [Parameter(Mandatory=$true)][double[]]$TrialScores,
  [Parameter(Mandatory=$true)][int[]]$TrialErrors,
  [Parameter(Mandatory=$true)][int[]]$TrialIterations,
  [switch]$OutputJson
)

if ($TrialToolCalls.Count -ne 3 -or $TrialTokens.Count -ne 3 -or $TrialScores.Count -ne 3 -or $TrialErrors.Count -ne 3 -or $TrialIterations.Count -ne 3) {
  Write-Error "Each Trial* parameter must have exactly 3 values."
  exit 1
}

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

try {

$avgToolCalls = [Math]::Round(($TrialToolCalls | Measure-Object -Average).Average, 1)
$avgTokens    = [Math]::Round(($TrialTokens | Measure-Object -Average).Average, 0)
$avgScore     = [Math]::Round(($TrialScores | Measure-Object -Average).Average, 1)
$avgErrors    = [Math]::Round(($TrialErrors | Measure-Object -Average).Average, 1)
$avgIter      = [Math]::Round(($TrialIterations | Measure-Object -Average).Average, 1)

function Get-Delta {
  param([double]$baseline, [double]$avg, [switch]$invert)
  if ($baseline -eq 0 -and $avg -eq 0) { return "0.0" }
  if ($baseline -eq 0) { if ($invert) { return "+100.0" } else { return "-100.0" } }
  $raw = [Math]::Round((($avg - $baseline) / $baseline) * 100, 1)
  if ($invert) { $raw = $raw * -1 }
  if ($raw -ge 0) { return "+$raw" } else { return "$raw" }
}

$deltaCalls    = Get-Delta -baseline $BaselineToolCalls -avg $avgToolCalls -invert
$deltaTokens   = Get-Delta -baseline $BaselineTokens -avg $avgTokens -invert
$deltaScore    = Get-Delta -baseline $BaselineScore -avg $avgScore
$deltaErrors   = Get-Delta -baseline $BaselineErrors -avg $avgErrors -invert
$deltaIter     = Get-Delta -baseline $BaselineIterations -avg $avgIter -invert

function Get-Num {
  param([string]$s)
  return [double]($s -replace '[+]','')
}

$ndCalls  = Get-Num $deltaCalls
$ndTokens = Get-Num $deltaTokens
$ndScore  = Get-Num $deltaScore
$ndErrors = Get-Num $deltaErrors
$ndIter   = Get-Num $deltaIter

$metrics = @(
  @{name="Tool calls"; val=$ndCalls},
  @{name="Tokens"; val=$ndTokens},
  @{name="Score"; val=$ndScore},
  @{name="Errors"; val=$ndErrors},
  @{name="Iterations"; val=$ndIter}
)

$countGe20 = 0
$countGe10 = 0
$countGe5 = 0
$countNeg = 0
foreach ($m in $metrics) {
  if ($m.val -ge 20) { $countGe20++ }
  if ($m.val -ge 10) { $countGe10++ }
  if ($m.val -ge 5)  { $countGe5++ }
  if ($m.val -lt 5)  { $countNeg++ }
}

$verdict = ""
$action = ""
$symbol = ""

if ($countGe20 -ge 3 -and $avgScore -ge 7) {
  $verdict = "EXCELLENT"
  $action = "prioritize in skill-registry + mem_save pattern"
  $symbol = "(EX)"
} elseif ($countGe10 -ge 3 -and $avgScore -ge 7) {
  $verdict = "KEEP"
  $action = "register in skill-registry"
  $symbol = "(OK)"
} elseif ($countGe5 -ge 2) {
  $verdict = "IMPROVE"
  $action = "run skill-improver to polish"
  $symbol = "(IM)"
} elseif ($countNeg -ge 2 -or $avgScore -lt 7) {
  $verdict = "DISCARD"
  $action = "run skill-improver prune + mem_save discard reason"
  $symbol = "(XX)"
} else {
  $verdict = "UNCLEAR"
  $action = "re-evaluate with more trials"
  $symbol = "(??)"
}

$report = "SkillValidation: $SkillName"
$report += "`n| Metric | Baseline | Avg 3 Trials | Delta |"
$report += "`n|--------|----------|-------------|-------|"
$report += "`n| Tool calls | $BaselineToolCalls | $avgToolCalls | $deltaCalls |"
$report += "`n| Tokens | $BaselineTokens | $avgTokens | $deltaTokens |"
$report += "`n| Score | $BaselineScore | $avgScore | $deltaScore |"
$report += "`n| Errors | $BaselineErrors | $avgErrors | $deltaErrors |"
$report += "`n| Iterations | $BaselineIterations | $avgIter | $deltaIter |"
$report += "`n`n**Verdict**: $symbol $verdict"
$report += "`n**Action**: $action"
$report += "`n**Trial scores**: $($TrialScores -join ', ')"
$report += "`n**Avg score**: $avgScore"

$scoring = "`n### SkillsBench Decision Table"
$scoring += "`n| Condition | Met? | Count |"
$scoring += "`n|-----------|------|-------|"
if ($countGe20 -ge 3 -and $avgScore -ge 7) { $scoring += "`n| Delta >=20% in >=3 metrics (avg>=7) | YES | $countGe20 metrics |" } else { $scoring += "`n| Delta >=20% in >=3 metrics (avg>=7) | no | $countGe20 metrics |" }
if ($countGe10 -ge 3 -and $avgScore -ge 7) { $scoring += "`n| Delta >=10% in >=3 metrics (avg>=7) | YES | $countGe10 metrics |" } else { $scoring += "`n| Delta >=10% in >=3 metrics (avg>=7) | no | $countGe10 metrics |" }
if ($countGe5 -ge 2) { $scoring += "`n| Delta >=5% in >=2 metrics | YES | $countGe5 metrics |" } else { $scoring += "`n| Delta >=5% in >=2 metrics | no | $countGe5 metrics |" }
if ($countNeg -ge 2 -or $avgScore -lt 7) { $scoring += "`n| Delta <5% in >=2 or avg<7 | YES | $countNeg metrics <5% |" } else { $scoring += "`n| Delta <5% in >=2 or avg<7 | no | $countNeg metrics <5% |" }

  # ponytail: -Quiet suppresses informational report/scoring tables, keeps JSON data only
  if ($OutputJson -or $Quiet) {
    $result = @{
      skill = $SkillName
      verdict = $verdict
      symbol = $symbol
      action = $action
      avgScore = $avgScore
      deltas = @{
        toolCalls = $deltaCalls
        tokens = $deltaTokens
        score = $deltaScore
        errors = $deltaErrors
        iterations = $deltaIter
      }
      counts = @{
        ge20 = $countGe20
        ge10 = $countGe10
        ge5 = $countGe5
        neg = $countNeg
      }
    }
    Write-Output ($result | ConvertTo-Json -Depth 3)
  } else {
    Write-Output $report
    Write-Output $scoring
  }
} catch {
    Write-Error "skill-validate failed: $_"
    throw
}
