#requires -Version 7
<#
.SYNOPSIS
    Shared template-detection module — SSoT for agent → permission-template mapping.
.DESCRIPTION
    Split from use-gentleman.ps1 so tests can dot-source this module WITHOUT executing
    the full config-generation script (which writes opencode.json and has side effects).

    Mirrors scripts/lib/generate-opencode-config.js detectTemplate() — same logic,
    same precedence. Keep both in sync.

    Resolution order (first match wins):
      1. Explicit $TemplateMap — SSOT anchor, manual entries always win
      2. Suffix auto-registration (-sub-auto → auto-sub, -auto → auto, -semi → semi, -sub → recurse)
      3. Role keyword matching (security/infra/docs/... → readonly, reviewer → reviewer, vMK → orchestrator)
      4. Fail-closed — throw if no match
#>

# ── Explicit map — SSOT anchor (mirrors TEMPLATE_MAP in generate-opencode-config.js) ──
# Every agent here MUST match the JS map. Drift = bug.
$TemplateMap = @{
    # Orchestrator
    'gentleman-vMK' = 'orchestrator'
    'gentle-orchestrator' = 'sddorchestrator'
    'gentleman-vMK-semi' = 'semi'

    # Read-only specialists
    'gentleman-security'     = 'readonly'
    'gentleman-seo'          = 'readonly'
    'gentleman-infra'        = 'readonly'
    'gentleman-frontend'     = 'readonly'
    'gentleman-performance'  = 'readonly'
    'gentleman-datascience'  = 'readonly'
    'gentleman-docs'         = 'readonly'

    # Read/write agents
    'gentleman-deep'          = 'readwrite'
    'gentleman-quick'         = 'readwrite'
    'gentleman-codex'         = 'readwrite'
    'gentleman-implementer'   = 'readwrite'

    # Subagent twins (mode: subagent, hidden: true)
    'gentleman-deep-sub'          = 'readwrite'
    'gentleman-quick-sub'         = 'readwrite'
    'gentleman-implementer-sub'   = 'readwrite'
    'gentleman-codex-sub'         = 'readwrite'   # FIX: was missing from PS map
    'gentleman-security-sub'      = 'readonly'
    'gentleman-seo-sub'           = 'readonly'
    'gentleman-infra-sub'         = 'readonly'
    'gentleman-frontend-sub'      = 'readonly'
    'gentleman-performance-sub'   = 'readonly'
    'gentleman-datascience-sub'   = 'readonly'
    'gentleman-docs-sub'          = 'readonly'
    'gentleman-reviewer-sub'      = 'reviewer'    # FIX: was missing from PS map

    # SDD agents
    'sdd-apply'     = 'readwrite'
    'sdd-archive'   = 'readwrite'
    'sdd-design'    = 'readwrite'
    'sdd-explore'   = 'readwrite'
    'sdd-init'      = 'readwrite'
    'sdd-verify'    = 'readwrite'
    'sdd-propose'   = 'readwrite'
    'sdd-spec'      = 'readwrite'
    'sdd-tasks'     = 'readwrite'
    'sdd-orchestrator' = 'sddorchestrator'

    # Mode variants — AUTO (zero-ask)
    'gentleman-vMK-auto'           = 'auto'
    'gentleman-deep-auto'          = 'auto'
    'gentleman-quick-auto'         = 'auto'
    'gentleman-codex-auto'         = 'auto'
    'gentleman-implementer-auto'   = 'auto'

    # Mode variants — AUTO-SUB (zero-ask, subagent)
    'gentleman-deep-sub-auto'          = 'auto-sub'   # FIX: was 'auto' (drift)
    'gentleman-quick-sub-auto'         = 'auto-sub'   # FIX: was 'auto' (drift)
    'gentleman-codex-sub-auto'         = 'auto-sub'   # FIX: was 'auto' (drift)
    'gentleman-implementer-sub-auto'   = 'auto-sub'   # FIX: was 'auto' (drift)

    # Mode variants — SEMI
    'gentleman-deep-semi'        = 'semi'
    'gentleman-quick-semi'       = 'semi'
    'gentleman-codex-semi'       = 'semi'
    'gentleman-implementer-semi' = 'semi'

    # Reviewer
    'gentleman-reviewer' = 'reviewer'
}

# ── Role keywords for auto-registration (checked when not in explicit map) ──
$RoleKeywords = @{
    'security'    = 'readonly'
    'infra'       = 'readonly'
    'docs'        = 'readonly'
    'seo'         = 'readonly'
    'frontend'    = 'readonly'
    'performance' = 'readonly'
    'datascience' = 'readonly'
    'reviewer'    = 'reviewer'
    'vMK'         = 'orchestrator'
}

<#
.SYNOPSIS
    Detect permission template for an agent name.
.DESCRIPTION
    1. Explicit lookup in $TemplateMap (SSOT anchor)
    2. Suffix auto-registration (-sub-auto → auto-sub, -auto → auto, -semi → semi, -sub → recurse)
    3. Role keyword matching (security/infra/... → readonly)
    4. Fail-closed — throw if no match

    Mirrors detectTemplate() in generate-opencode-config.js exactly.
.EXAMPLE
    Detect-Template -AgentName 'gentleman-codex-sub-auto'  # → 'auto-sub'
    Detect-Template -AgentName 'gentleman-security-sub'   # → 'readonly'
    Detect-Template -AgentName 'gentleman-biz'             # → throws
#>
function Detect-Template {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Detect-Template mirrors detectTemplate() in generate-opencode-config.js for cross-file parity')]
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AgentName
    )

    # 1. Explicit lookup — SSOT anchor, always wins
    if ($TemplateMap.ContainsKey($AgentName)) {
        return $TemplateMap[$AgentName]
    }

    # 2. Suffix auto-registration (longest suffix first)
    if ($AgentName -match '-sub-auto$') { return 'auto-sub' }
    if ($AgentName -match '-semi$')      { return 'semi' }
    if ($AgentName -match '-auto$')     { return 'auto' }
    if ($AgentName -match '-sub$')      {
        $parent = $AgentName -replace '-sub$', ''
        return Detect-Template -AgentName $parent
    }

    # 3. Role keyword matching
    foreach ($kw in $RoleKeywords.GetEnumerator()) {
        if ($AgentName -match $kw.Key) { return $kw.Value }
    }

    # 4. Fail-closed
    throw "No template mapping found for agent '$AgentName'. Add explicit entry to `$TemplateMap or follow naming conventions."
}
