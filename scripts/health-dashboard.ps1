#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Generates a visual HTML health report from health-check-system.ps1.
.DESCRIPTION
    Runs the health check, parses JSON output, and produces a self-contained
    HTML dashboard at docs/health-report.html.
.PARAMETER OutputPath
    Path for the generated HTML file. Default: docs/health-report.html
.PARAMETER OpenInBrowser
    Opens the report in the default browser after generating.
.EXAMPLE
    ./scripts/health-dashboard.ps1
    ./scripts/health-dashboard.ps1 -OutputPath report.html -OpenInBrowser
#>
param(
    [string]$OutputPath = "docs\health-report.html",
    [switch]$OpenInBrowser
)
Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$healthCheck = Join-Path $scriptDir "health-check-system.ps1"

if (-not (Test-Path $healthCheck)) {
    throw "health-check-system.ps1 not found at $healthCheck"
}

# Run the health check and capture JSON output
$jsonOutput = & $healthCheck -Json
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Health check exited with code $LASTEXITCODE (non-zero is normal when failures exist)"
}
$checks = $jsonOutput | ConvertFrom-Json

# Tally results
$total = $checks.Count
$okCount = 0
$warnCount = 0
$failCount = 0
$skipCount = 0

foreach ($c in $checks) {
    switch ($c.Status) {
        "OK"   { $okCount++ }
        "WARN" { $warnCount++ }
        "FAIL" { $failCount++ }
        default { $skipCount++ }
    }
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Build table rows
$tableRows = ""
foreach ($c in $checks) {
    $icon = "&#x2753;"
    $rowClass = "skip"
    switch ($c.Status) {
        "OK"   { $icon = "&#x2705;"; $rowClass = "ok" }
        "WARN" { $icon = "&#x26A0;&#xFE0F;"; $rowClass = "warn" }
        "FAIL" { $icon = "&#x274C;"; $rowClass = "fail" }
    }
    $escapedName = [System.Net.WebUtility]::HtmlEncode($c.Check)
    $escapedDetail = [System.Net.WebUtility]::HtmlEncode(($c.Detail | Out-String).Trim())
    $tableRows += "      <tr class=`"$rowClass`"><td class=`"icon`">$icon</td><td>$escapedName</td><td>$escapedDetail</td><td>$($c.Status)</td></tr>`n"
}

# Summary bar color classes
$okBarClass = if ($okCount -gt 0) { "sum-ok" } else { "sum-empty" }
$warnBarClass = if ($warnCount -gt 0) { "sum-warn" } else { "sum-empty" }
$failBarClass = if ($failCount -gt 0) { "sum-fail" } else { "sum-empty" }
$skipBarClass = if ($skipCount -gt 0) { "sum-skip" } else { "sum-empty" }

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Gentleman Agent Health Report</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0f0f0f;color:#e0e0e0;padding:24px;min-height:100vh}
  .container{max-width:800px;margin:0 auto}
  h1{font-size:1.5rem;margin-bottom:4px;color:#fff}
  .timestamp{font-size:.85rem;color:#888;margin-bottom:20px}
  .summary{display:flex;gap:12px;margin-bottom:24px;flex-wrap:wrap}
  .sum-pill{padding:10px 18px;border-radius:8px;font-weight:600;font-size:.95rem;flex:1;min-width:100px;text-align:center}
  .sum-ok{background:#0d3320;color:#34d399;border:1px solid #166534}
  .sum-warn{background:#3b2f0a;color:#fbbf24;border:1px solid #92400e}
  .sum-fail{background:#3b0a0a;color:#f87171;border:1px solid #991b1b}
  .sum-skip{background:#1a1a2a;color:#7c8aaa;border:1px solid #333}
  .sum-empty{background:#1a1a1a;color:#555;border:1px solid #333}
  table{width:100%;border-collapse:collapse;font-size:.9rem}
  th{text-align:left;padding:10px 12px;border-bottom:2px solid #333;color:#aaa;font-weight:600}
  td{padding:10px 12px;border-bottom:1px solid #222}
  td.icon{text-align:center;width:40px}
  tr.ok td{background:#0a1f14}
  tr.warn td{background:#1f1a0a}
  tr.fail td{background:#1f0a0a}
  tr.skip td{background:#151520;color:#888}
  .footer{margin-top:20px;text-align:center;font-size:.75rem;color:#555}
  @media(max-width:600px){
    body{padding:12px}
    .sum-pill{min-width:80px;padding:8px 10px;font-size:.85rem}
    td{padding:8px 6px;font-size:.8rem}
  }
</style>
</head>
<body>
<div class="container">
  <h1>Gentleman Agent Health Report</h1>
  <p class="timestamp">Generated: $timestamp</p>
  <div class="summary">
    <div class="sum-pill $okBarClass">$okCount OK</div>
    <div class="sum-pill $warnBarClass">$warnCount WARN</div>
    <div class="sum-pill $failBarClass">$failCount FAIL</div>
    <div class="sum-pill $skipBarClass">$skipCount SKIP</div>
  </div>
  <table>
    <thead><tr><th></th><th>Check</th><th>Detail</th><th>Status</th></tr></thead>
    <tbody>
$tableRows    </tbody>
  </table>
  <p class="footer">Health check ran $total checks &middot; $okCount passed, $warnCount warnings, $failCount failures</p>
</div>
</body>
</html>
"@

# Ensure output directory exists
$outputDir = Split-Path -Parent $OutputPath
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

Write-Output "Health: $okCount/$total checks OK ($warnCount warnings, $failCount failures) -> $OutputPath"

if ($OpenInBrowser) {
    Start-Process $OutputPath
}
