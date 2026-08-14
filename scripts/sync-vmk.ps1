#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Sync canonical config from gentleman-agent-gh to opencode-global.
  Part of P3 — Autonomous Integration Plan.
.DESCRIPTION
  Sync: agent section, skills paths, permission rules, plugin list.
  Does NOT sync: MCP servers, default_agent (vmk uses vmk.cmd), DB schema.
.PARAMETER Target
  vmk | global | all (default: all)
.PARAMETER DryRun
  Show what would change without writing
.PARAMETER Force
  Skip confirmation prompts
#>
param(
  [ValidateSet("global")]
  [string]$Target = "global",
  [switch]$DryRun,
  [switch]$Force,
  [switch]$Json,
  [switch]$Quiet
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Cross-platform helpers ──────────────────────────────────────────────
. (Join-Path (Join-Path $PSScriptRoot "lib") "platform.ps1")
. (Join-Path $PSScriptRoot 'lib' 'json-utils.ps1')

$gentlemanRoot = Get-GentlemanRoot

$canonicalPath = (Join-Path $gentlemanRoot "opencode.json")
$globalConfig  = Get-GlobalConfigDir
$globalPath    = Join-Path $globalConfig "opencode.json"

# ── Validate canonical exists ────────────────────────────────────────────
if (-not (Test-Path $canonicalPath)) { Write-Error "Canonical config not found: $canonicalPath"; exit 1 }

# ── Read canonical ───────────────────────────────────────────────────────
$canonical = Get-Content -LiteralPath $canonicalPath -Raw -Encoding UTF8 | ConvertFrom-Json
$results = [System.Collections.Generic.List[object]]::new()

# ── Sync sections to a target ────────────────────────────────────────────
function Sync-Config {
  param([string]$TargetPath, [string]$Label, [bool]$PreserveMCP)
  if (-not (Test-Path $TargetPath)) {
    $results.Add(@{target=$Label; status="SKIP"; detail="File not found"})
    return
  }
  $target = Get-Content -LiteralPath $TargetPath -Raw -Encoding UTF8 | ConvertFrom-Json

  $changes = @()
  # agent section (from canonical)
  if ($canonical.agent) {
    $canonicalAgent = $canonical.agent | ConvertTo-Json -Depth 10 -Compress
    $targetAgent = $target.agent | ConvertTo-Json -Depth 10 -Compress
    if ($canonicalAgent -ne $targetAgent) { $changes += "agent" }
  }
  # permission (from canonical)
  if ($canonical.permission) {
    $canonicalPerm = $canonical.permission | ConvertTo-Json -Depth 10 -Compress
    $targetPerm = if ($target.PSObject.Properties['permission']) { $target.permission | ConvertTo-Json -Depth 10 -Compress } else { "null" }
    if ($canonicalPerm -ne $targetPerm) { $changes += "permission" }
  }
  # skills paths (from canonical, adjust for target)
  if ($canonical.PSObject.Properties['skills']) {
    $canonicalSkills = $canonical.skills | ConvertTo-Json -Depth 5 -Compress
    $targetSkills = if ($target.PSObject.Properties['skills']) { $target.skills | ConvertTo-Json -Depth 5 -Compress } else { "null" }
    if ($canonicalSkills -ne $targetSkills) { $changes += "skills" }
  }
  # plugin list (from canonical — replace, don't merge)
  if ($canonical.PSObject.Properties['plugin']) {
    $canonicalPlugin = $canonical.plugin | ConvertTo-Json -Compress
    $targetPlugin = if ($target.PSObject.Properties['plugin']) { $target.plugin | ConvertTo-Json -Compress } else { "null" }
    if ($canonicalPlugin -ne $targetPlugin) { $changes += "plugin" }
  }
  # limit (context window threshold — new in v2)
  if ($canonical.PSObject.Properties['limit']) {
    $canonicalLimit = $canonical.limit | ConvertTo-Json -Compress
    $targetLimit   = if ($target.PSObject.Properties['limit'])   { $target.limit   | ConvertTo-Json -Compress } else { "null" }
    if ($canonicalLimit -ne $targetLimit) { $changes += "limit" }
  }
  # compaction (prune + reserved)
  if ($canonical.PSObject.Properties['compaction']) {
    $canonicalComp = $canonical.compaction | ConvertTo-Json -Compress
    $targetComp    = if ($target.PSObject.Properties['compaction']) { $target.compaction | ConvertTo-Json -Compress } else { "null" }
    if ($canonicalComp -ne $targetComp) { $changes += "compaction" }
  }
  # tool_output (max_lines / max_bytes)
  if ($canonical.PSObject.Properties['tool_output']) {
    $canonicalTout = $canonical.tool_output | ConvertTo-Json -Compress
    $targetTout    = if ($target.PSObject.Properties['tool_output']) { $target.tool_output | ConvertTo-Json -Compress } else { "null" }
    if ($canonicalTout -ne $targetTout) { $changes += "tool_output" }
  }
  # experimental (feature flags)
  if ($canonical.PSObject.Properties['experimental']) {
    $canonicalExp = $canonical.experimental | ConvertTo-Json -Compress
    $targetExp    = if ($target.PSObject.Properties['experimental']) { $target.experimental | ConvertTo-Json -Compress } else { "null" }
    if ($canonicalExp -ne $targetExp) { $changes += "experimental" }
  }
  # tools (engram*, codebase-memory* allow/deny)
  if ($canonical.PSObject.Properties['tools']) {
    $canonicalTools = $canonical.tools | ConvertTo-Json -Compress
    $targetTools    = if ($target.PSObject.Properties['tools']) { $target.tools | ConvertTo-Json -Compress } else { "null" }
    if ($canonicalTools -ne $targetTools) { $changes += "tools" }
  }

  if ($changes.Count -eq 0) {
    $results.Add(@{target=$Label; status="OK"; detail="No changes needed"})
    return
  }

  if ($DryRun) {
    $results.Add(@{target=$Label; status="DRY-RUN"; detail="Would update: $($changes -join ', ')"})
    return
  }

  # Apply changes (use Add-Member for properties that may not exist yet)
  if ($changes -contains "agent")      { $target.agent = $canonical.agent }
  if ($changes -contains "permission") {
    if ($target.PSObject.Properties['permission']) { $target.permission = $canonical.permission }
    else { $target | Add-Member -Name "permission" -Value $canonical.permission -MemberType NoteProperty -Force }
  }
  if ($changes -contains "skills")     {
    if ($target.PSObject.Properties['skills']) { $target.skills = $canonical.skills }
    else { $target | Add-Member -Name "skills" -Value $canonical.skills -MemberType NoteProperty }
  }
  if ($changes -contains "plugin")     {
    if ($target.PSObject.Properties['plugin']) { $target.plugin = $canonical.plugin }
    else { $target | Add-Member -Name "plugin" -Value $canonical.plugin -MemberType NoteProperty }
  }
  if ($changes -contains "limit") {
    if ($target.PSObject.Properties['limit']) { $target.limit = $canonical.limit }
    else { $target | Add-Member -Name "limit" -Value $canonical.limit -MemberType NoteProperty }
  }
  if ($changes -contains "compaction") {
    if ($target.PSObject.Properties['compaction']) { $target.compaction = $canonical.compaction }
    else { $target | Add-Member -Name "compaction" -Value $canonical.compaction -MemberType NoteProperty }
  }
  if ($changes -contains "tool_output") {
    if ($target.PSObject.Properties['tool_output']) { $target.tool_output = $canonical.tool_output }
    else { $target | Add-Member -Name "tool_output" -Value $canonical.tool_output -MemberType NoteProperty }
  }
  if ($changes -contains "experimental") {
    if ($target.PSObject.Properties['experimental']) { $target.experimental = $canonical.experimental }
    else { $target | Add-Member -Name "experimental" -Value $canonical.experimental -MemberType NoteProperty }
  }
  if ($changes -contains "tools") {
    if ($target.PSObject.Properties['tools']) { $target.tools = $canonical.tools }
    else { $target | Add-Member -Name "tools" -Value $canonical.tools -MemberType NoteProperty }
  }

  # MCP is preserved by design (managed separately by global-setup.ps1).
  # With PreserveMCP=true (default) an mcp section is never compared nor synced;
  # with -PreserveMCP:$false the repo config's mcp section wins over the target's.
  if (-not $PreserveMCP -and $canonical.PSObject.Properties['mcp']) {
    $target | Add-Member -Name "mcp" -Value $canonical.mcp -MemberType NoteProperty -Force
  }

   $jsonStr = ConvertTo-JsonSafe -InputObject $target -Depth 10
   $jsonStr | Set-Content -LiteralPath $TargetPath -Encoding UTF8
   $results.Add(@{target=$Label; status="SYNCED"; detail="Updated: $($changes -join ', ')"})
}

# ── Execute ──────────────────────────────────────────────────────────────
if ($env:PESTER_TEST -eq '1') {
  # Test mode: never write the user's real global config (opencode.json / AGENTS.md).
  # Sync-Config stays available for tests that pass their own temp TargetPath.
  Write-Warning "PESTER_TEST=1 — skipping global config apply (test mode)"
} elseif ($Target -eq "global") {
  Sync-Config -TargetPath $globalPath -Label "global" -PreserveMCP $true
  if (-not $DryRun) {
    $agentsMdDest = Join-Path $globalConfig "AGENTS.md"
    if ((Test-Path $agentsMdDest) -and -not $Force) {
      $results.Add(@{target="global-agents-md"; status="SKIP"; detail="AGENTS.md already exists (use -Force to overwrite)"})
    } else {
      Copy-Item -LiteralPath (Join-Path $gentlemanRoot "AGENTS.md") $agentsMdDest -Force -ErrorAction SilentlyContinue
      $results.Add(@{target="global-agents-md"; status="SYNCED"; detail="AGENTS.md copied"})
    }
  } else {
    $results.Add(@{target="global-agents-md"; status="DRY-RUN"; detail="Would copy AGENTS.md"})
  }
}

# ── Output ──────────────────────────────────────────────────────────────
if ($Json) {
  ConvertTo-Json @{timestamp=(Get-Date -Format "o"); results=$results} -Depth 3
} elseif (-not $Quiet) {
  $results | ForEach-Object {
    $icon = switch ($_.status) { "OK" { "✅" } "SYNCED" { "🔄" } "DRY-RUN" { "🔍" } "SKIP" { "⏭️" } default { "❓" } }
    Write-Output "$icon $($_.target): $($_.detail)"
  }
}
