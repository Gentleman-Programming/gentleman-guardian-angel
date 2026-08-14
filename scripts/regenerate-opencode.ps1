#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Regenerate opencode.json from the SSoT (scripts/lib/*) via the node generator, then verify the result.

.DESCRIPTION
  Wraps `node scripts/lib/generate-opencode-config.js` so the orchestrator can regenerate
  opencode.json without invoking node directly (node * is in the orchestrator deny list).
  Two modes:
    - Validate (default): runs `--validate` against the existing opencode.json.
      Exit 0 = in sync. Exit 1 = mismatch (opencode.json is stale vs SSoT).
    - -Yes: writes opencode.json, then runs structural verification:
      1. The 4 subagent twins exist (mode: subagent, hidden: true)
      2. Orchestrator task whitelist is fail-closed ("*": "deny") and allows the 4 twins
      3. Read-only agents (incl. gentleman-security-sub) deny bash.*
      4. JSON is parseable and opencode.json is valid against the node generator --validate
  SAFE BY DEFAULT: without -Yes this script never writes anything.

.PARAMETER Yes
  Write opencode.json (regenerate). Without it, only validates.

.PARAMETER RepoRoot
  Repository root. Default: git root detected from the current directory.

.PARAMETER Quiet
  JSON-only summary on stdout.

.PARAMETER MaxBytes
  Size budget for opencode.json (default: 65536). Fails the post-write verification
  if the regenerated file exceeds it — guards against unbounded config growth.

.EXAMPLE
  & scripts/regenerate-opencode.ps1            # validate: is opencode.json in sync?
  & scripts/regenerate-opencode.ps1 -Yes       # regenerate + verify
  & scripts/regenerate-opencode.ps1 -Yes -Quiet  # machine-readable summary
#>
param(
  [switch]$Yes,
  [string]$RepoRoot = (Get-Location).Path,
  [switch]$Quiet,
  [int]$MaxBytes = 98304
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Locate repo root (walk up to .git) ---
$root = (Resolve-Path -LiteralPath $RepoRoot).Path
while ($root -and -not (Test-Path (Join-Path $root '.git'))) {
  $root = Split-Path $root -Parent
}
if (-not $root) { throw "No git root found under: $RepoRoot" }

$generator = Join-Path $root 'scripts\lib\generate-opencode-config.js'
$output = Join-Path $root 'opencode.json'
if (-not (Test-Path -LiteralPath $generator)) { throw "Generator not found: $generator" }

# --- Locate node (wrapper is the ONLY sanctioned path for the orchestrator) ---
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { throw 'node not found on PATH — cannot regenerate opencode.json' }

$result = [ordered]@{ status = 'fail'; mode = 'validate'; checks = @() }

function Add-Check {
  param([string]$Name, [bool]$Pass, [string]$Detail)
  $script:result.checks += [ordered]@{ name = $Name; pass = $Pass; detail = $Detail }
}

# --- Mode 1: validate against existing opencode.json ---
& $node $generator --validate 2>&1 | ForEach-Object { $_ }
$validateExit = $LASTEXITCODE

if ($validateExit -ne 0) {
  Add-Check 'pre-write-validate' $false 'MISMATCH — opencode.json was stale vs SSoT (expected pre-write). Run with -Yes to regenerate.'
} else {
  Add-Check 'pre-write-validate' $true 'in sync with SSoT'
}

if (-not $Yes) {
  $result.status = if ($validateExit -eq 0) { 'ok' } else { 'stale' }
  if ($Quiet) { $result | ConvertTo-Json -Depth 5 | Write-Output } else {
    Write-Output "[regenerate-opencode] validate-only: $(if ($validateExit -eq 0) { 'OK — in sync' } else { 'STALE — run -Yes to regenerate' })"
  }
  exit $validateExit
}

# In write mode the pre-write mismatch is EXPECTED (that's why we regenerate) —
# reclassify it as informational so it never flips the final status.
$preWrite = @($result.checks | Where-Object { $_.name -eq 'pre-write-validate' })[0]
if ($preWrite) { $preWrite.pass = $true; $preWrite.detail = 'pre-write state: stale (regenerated below)' }

# --- Mode 2: write ---
& $node $generator 2>&1 | ForEach-Object { $_ }
if ($LASTEXITCODE -ne 0) { throw 'Generator write failed — opencode.json left untouched (write is atomic-ish, verify before retry)' }
$result.mode = 'write'

# --- Verify written opencode.json ---
try {
  $cfg = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
  Add-Check 'json-parse' $true 'opencode.json parses as JSON'
} catch {
  Add-Check 'json-parse' $false $_.Exception.Message
  $result.status = 'fail'
  if ($Quiet) { $result | ConvertTo-Json -Depth 5 | Write-Output }
  exit 1
}

$sizeBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $output)).Length
if ($sizeBytes -gt $MaxBytes) {
  Add-Check 'config-size-budget' $false "$sizeBytes B > budget $MaxBytes B (grew unbounded — review agent/permission additions)"
} else {
  Add-Check 'config-size-budget' $true "$sizeBytes B within budget $MaxBytes B"
}

$twins = @('gentleman-deep-sub', 'gentleman-quick-sub', 'gentleman-implementer-sub', 'gentleman-security-sub', 'gentleman-seo-sub', 'gentleman-infra-sub', 'gentleman-frontend-sub', 'gentleman-performance-sub', 'gentleman-datascience-sub', 'gentleman-docs-sub')
$autoTwins = @('gentleman-deep-sub-auto', 'gentleman-quick-sub-auto', 'gentleman-codex-sub-auto', 'gentleman-implementer-sub-auto')
foreach ($t in $twins) {
  $a = $cfg.agent.$t
  if (-not $a) { Add-Check "twin-$t" $false 'missing from opencode.json' }
  elseif ($a.mode -ne 'subagent' -or $a.hidden -ne $true) { Add-Check "twin-$t" $false "mode=$($a.mode) hidden=$($a.hidden) (expected subagent/true)" }
  else { Add-Check "twin-$t" $true 'mode:subagent hidden:true' }
}
foreach ($t in $autoTwins) {
  $a = $cfg.agent.$t
  if (-not $a) { Add-Check "auto-twin-$t" $false 'missing from opencode.json' }
  elseif ($a.mode -ne 'subagent' -or $a.hidden -ne $true) { Add-Check "auto-twin-$t" $false "mode=$($a.mode) hidden=$($a.hidden) (expected subagent/true)" }
  elseif ($a.permission.bash.'*' -ne 'allow') { Add-Check "auto-twin-$t" $false "bash.*=$($a.permission.bash.'*') (expected allow)" }
  else {
    $askCount = @($a.permission.bash.PSObject.Properties | Where-Object { $_.Value -eq 'ask' }).Count
    if ($askCount -gt 0) { Add-Check "auto-twin-$t" $false "$askCount ask entries (expected 0 — auto-sub must have zero ask)" }
    else { Add-Check "auto-twin-$t" $true 'subagent hidden:true bash:*=allow ask=0' }
  }
}

$orch = $cfg.agent.'gentleman-vMK'.permission
$orchTask = $orch.task
if (-not $orchTask -or $orchTask.'*' -ne 'deny') {
  Add-Check 'orch-task-failclosed' $false "task.* = $($orchTask.'*') (expected deny)"
} else {
  $missing = $twins | Where-Object { $orchTask.$_ -ne 'allow' }
  if ($missing) { Add-Check 'orch-task-failclosed' $false "twins not allowed: $($missing -join ', ')" }
  else { Add-Check 'orch-task-failclosed' $true "fail-closed with all $($twins.Count) base twins allowed" }
}

# Verify gentleman-vMK-auto can delegate to -sub-auto twins (fail-closed task allowlist)
$orchAuto = $cfg.agent.'gentleman-vMK-auto'.permission
$orchAutoTask = $orchAuto.task
if (-not $orchAutoTask -or $orchAutoTask.'*' -ne 'deny') {
  Add-Check 'orch-auto-task-failclosed' $false "vMK-auto task.* = $($orchAutoTask.'*') (expected deny)"
} else {
  $missingAuto = $autoTwins | Where-Object { $orchAutoTask.$_ -ne 'allow' }
  if ($missingAuto) { Add-Check 'orch-auto-task-failclosed' $false "vMK-auto not allowed: $($missingAuto -join ', ')" }
  else { Add-Check 'orch-auto-task-failclosed' $true "vMK-auto fail-closed with $($autoTwins.Count) auto-sub twins allowed" }
}

$readOnly = @('gentleman-security', 'gentleman-seo', 'gentleman-infra', 'gentleman-frontend', 'gentleman-performance', 'gentleman-datascience', 'gentleman-docs', 'gentleman-security-sub', 'gentleman-seo-sub', 'gentleman-infra-sub', 'gentleman-frontend-sub', 'gentleman-performance-sub', 'gentleman-datascience-sub', 'gentleman-docs-sub')
$roFail = @($readOnly | Where-Object { $cfg.agent.$_.permission.bash.'*' -ne 'deny' })
if ($roFail) { Add-Check 'readonly-bash-deny' $false "not deny: $($roFail -join ', ')" }
else { Add-Check 'readonly-bash-deny' $true "$($readOnly.Count) read-only agents deny bash.*" }

# --- Final: re-validate (the written file MUST satisfy --validate) ---
& $node $generator --validate 2>&1 | ForEach-Object { $_ }
if ($LASTEXITCODE -eq 0) { Add-Check 'post-write-validate' $true 'regenerated file in sync' }
else { Add-Check 'post-write-validate' $false 'post-write validation failed (should never happen)' }

$failed = @($result.checks | Where-Object { -not $_.pass })
$result.status = if ($failed.Count -eq 0) { 'ok' } else { 'fail' }

if ($Quiet) {
  $result | ConvertTo-Json -Depth 5 | Write-Output
} else {
  Write-Output ''
  Write-Output "[regenerate-opencode] $($result.status.ToUpper()) — $($result.checks.Count) checks, $($failed.Count) failed"
  foreach ($c in $result.checks) {
    $icon = if ($c.pass) { 'OK ' } else { 'FAIL' }
    Write-Output "  [$icon] $($c.name): $($c.detail)"
  }
  Write-Output '  opencode.json regenerated from SSoT — no commit made (git status will show it modified).'
}
exit $failed.Count -eq 0 ? 0 : 1
