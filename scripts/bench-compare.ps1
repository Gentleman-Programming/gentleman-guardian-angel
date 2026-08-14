#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Benchmark trend — time-series aggregation of benchmarks/*.json + pinned baseline.
.DESCRIPTION
    Aggregates every dated snapshot in benchmarks/ plus the pinned baseline into
    a chronological table (last -Top entries). Columns:
    date | skills | junctions | avg-bytes | benchmark-seconds | token-estimate | delta-vs-prev
.PARAMETER Baseline
    Path to the pinned baseline file (default: repo-root benchmark-baseline.json).
.PARAMETER Json
    Emit the trend rows as JSON instead of a table.
.PARAMETER Top
    Number of most-recent entries to show (default: 10).
#>
param(
  [string]$Baseline = (Join-Path (Split-Path $PSScriptRoot -Parent) "benchmark-baseline.json"),
  [switch]$Json,
  [int]$Top = 10
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$r = Split-Path $PSScriptRoot -Parent
$sn = Join-Path $r "benchmarks"

function Get-Row {
  param($System, [string]$Date)
  $n = $System.PSObject.Properties.Name
  [PSCustomObject]@{
    Date = $Date
    Skills = $System.TotalSkills
    Junctions = $System.GlobalJunctionsOk
    AvgBytes = $System.AvgSkillBytes
    BenchmarkSeconds = if ($n -contains 'BenchmarkSeconds') { $System.BenchmarkSeconds } else { $null }
    TokenEstimate = if ($n -contains 'TokenEstimate') { $System.TokenEstimate } else { $null }
  }
}

$rows = [System.Collections.Generic.List[object]]::new()
if (Test-Path $Baseline) {
  $b = Get-Content $Baseline -Raw | ConvertFrom-Json
  if ($b.system) { $rows.Add((Get-Row $b.system "baseline")) }
}
if (Test-Path $sn) {
  Get-ChildItem $sn -Filter *.json | Sort-Object Name | ForEach-Object {
    try {
      $s = Get-Content $_.FullName -Raw | ConvertFrom-Json
      if (-not $s.system) { return }
      $rows.Add((Get-Row $s.system $_.BaseName))
    } catch { Write-Warning "bench-compare: skip $($_.Name): $($_.Exception.Message)" }
  }
}
if ($rows.Count -eq 0) {
  Write-Output "No benchmark data found (benchmarks/*.json or $Baseline)."
  exit 0
}

$from = [Math]::Max(0, $rows.Count - $Top)
$view = @($rows[$from..($rows.Count - 1)])
$prev = $null
$withDelta = foreach ($row in $view) {
  $delta = if ($prev) {
    $dS = $row.Skills - $prev.Skills
    $dB = $row.AvgBytes - $prev.AvgBytes
    "{0:+0;-0;0} skills, {1:+0;-0;0}B avg" -f $dS, $dB
  } else { "—" }
  $prev = $row
  $row | Select-Object *, @{n = 'DeltaVsPrev'; e = { $delta }}
}

if ($Json) {
  $withDelta | ConvertTo-Json -Depth 3
} else {
  $withDelta | Format-Table Date, Skills, Junctions, AvgBytes, BenchmarkSeconds, TokenEstimate, DeltaVsPrev -AutoSize
}
