#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Validate mem_save content before persisting to Engram — schema, injection, field completeness.
.DESCRIPTION
  Post-save gate that validates mem_save content structure. Checks for:
  - Required **What** field
  - Injection patterns (poisoning guard)
  - Field completeness per type
  - Domain-specific field extensions
  Works as pipeline filter or standalone.
.PARAMETER Content
  The content string to validate.
.PARAMETER Title
  The mem_save title (used for error messages).
.PARAMETER Type
  Observation type: bugfix|decision|pattern|learning|discovery|config.
.PARAMETER TopicKey
  Topic key for the save (checked for injection patterns).
.PARAMETER Strict
  Require all 4 canonical fields: What, Why, Where, Learned.
.PARAMETER DomainFields
  Additional valid field names beyond the canonical set (e.g. @("Exit code","Output") for command-wrapper).
.PARAMETER PassThru
  Return the input object if valid, $null if invalid.
.PARAMETER Quiet
  Exit code only: 0=valid, 1=warnings, 2=errors.
.PARAMETER Fix
  Auto-fix: prefix bare content with "**What**: Auto-detected" if missing.
.PARAMETER InputObject
  Supports pipeline: @{Title="..."; Content="..."; Type="..."; TopicKey="..."}
.EXAMPLE
  .\scripts\engram-validate.ps1 -Content "**What**: Fixed N+1 query" -Type bugfix
.EXAMPLE
  "**What**: test" | .\scripts\engram-validate.ps1 -Strict -Quiet
.EXAMPLE
  .\scripts\engram-validate.ps1 -Content "**What**: cmd | **Exit code**: 0 | **Output**: ok" -DomainFields @("Exit code","Output")
#>
param(
    [Parameter(ValueFromPipeline = $true)]
    [object]$Content,
    [string]$Title = "",
    [ValidateSet('bugfix','decision','pattern','learning','discovery','config','')]
    [string]$Type = "",
    [string]$TopicKey = "",
    [switch]$Strict,
    [string[]]$DomainFields,
    [switch]$PassThru,
    [switch]$Quiet,
    [switch]$Fix
)
begin {
    Set-StrictMode -Version Latest
    # --- Dot-source shared validation logic (single source of truth) ---
    . (Join-Path (Join-Path $PSScriptRoot "lib") "engram-validate-lib.ps1")
}

process {
    Test-EngramContent -Content $Content -Title $Title -Type $Type -TopicKey $TopicKey -Strict:$Strict -DomainFields $DomainFields -PassThru:$PassThru -Fix:$Fix -Quiet:$Quiet
}

end {
    # In Quiet mode, output nothing — caller reads $LASTEXITCODE from outside Pester
}
