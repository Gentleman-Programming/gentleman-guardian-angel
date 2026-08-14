#requires -Version 7
<#
.SYNOPSIS
    Shared mem_save content validation logic for Engram.
.DESCRIPTION
    Dot-sourced by scripts/engram-validate.ps1 (and by its Pester tests).
    Exposes:
    - Test-EngramContent: validates content (schema, injection, field completeness)
    - Write-ErrorMsg / Write-WarnMsg: emit warnings + drive $script:exitCode
      (0 = valid, 1 = warnings, 2 = errors) — the script's exit-code contract
.NOTES
    This file is NOT meant to be invoked directly.
    $script:exitCode and $script:engramQuiet live in the dot-sourcing caller's
    script scope (production script or test file). The caller sets
    $script:engramQuiet from its -Quiet switch; Test-EngramContent also
    derives it from its own -Quiet switch on every call.
#>

$script:exitCode = 0
$script:engramQuiet = $false

function Write-ErrorMsg { param([string]$Msg) $script:exitCode = 2; if (-not $script:engramQuiet) { Write-Warning "ERR: $Msg" } }
function Write-WarnMsg  { param([string]$Msg) if ($script:exitCode -lt 1) { $script:exitCode = 1 }; if (-not $script:engramQuiet) { Write-Warning "WARN: $Msg" } }

function Test-EngramContent {
    [CmdletBinding(SupportsShouldProcess=$true)]
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

    process {
    $script:engramQuiet = [bool]$Quiet

    $contentStr = ""
    $typeStr = $Type
    $topicStr = $TopicKey
    # $Title / $DomainFields are public contract (forwarded by scripts/engram-validate.ps1);
    # intentionally unused inside the function body — kept for the caller-facing signature.
    [void]$Title
    [void]$DomainFields

    if ($Content -is [string]) {
        $contentStr = $Content
    } elseif ($Content -is [hashtable]) {
        if ($Content.ContainsKey('Content')) { $contentStr = $Content['Content'] }
    }

    $errors = @()
    $warnings = @()
    $foundFields = @()

    # --- 1. Content empty check ---
    if ([string]::IsNullOrWhiteSpace($contentStr)) {
        if ($PassThru) { return $null }
        if (-not $script:engramQuiet) {
            Write-ErrorMsg "Content is empty"
            $result = [PSCustomObject]@{ valid = $false; errors = @("Content is empty"); warnings = @(); fields = @(); fixed = $false; content = $null }
            Write-Output $result
        }
        return
    }

    # --- 2. Extract **fields** (names + values) ---
    $fieldNameRegex = [regex]'\*\*([^*]+)\*\*'
    $fieldRegex = [regex]'\*\*([^*]+)\*\*\s*:\s*([^\n]*(?:\n(?!\*\*)[^\n]*)*)'
    $foundFields = @($fieldNameRegex.Matches($contentStr) | ForEach-Object { $_.Groups[1].Value.Trim() })
    $fieldValues = @{}
    foreach ($m in $fieldRegex.Matches($contentStr)) {
        $fname = $m.Groups[1].Value.Trim()
        $fvalue = $m.Groups[2].Value.Trim()
        if (-not $fieldValues.ContainsKey($fname)) { $fieldValues[$fname] = @() }
        $fieldValues[$fname] += $fvalue
    }

    # --- 3. Injection patterns ---
    $injectionPatterns = @("ignore previous", "forget instructions", "system prompt", "new instructions", "ignore all", "override", "new rule", "disregard", "you are now", "ignore everything", "forget previous", "system message", "ignore instructions", "forget all", "you are not", "disregard previous")
    # Homoglyph check: unicode chars that visually resemble ASCII (injection bypass defense)
    $homoglyphChars = @{
        [char]0x0430 = 'a'; # Cyrillic а → Latin a
        [char]0x0435 = 'e'; # Cyrillic е → Latin e
        [char]0x043E = 'o'; # Cyrillic о → Latin o
        [char]0x0441 = 'c'; # Cyrillic с → Latin c
        [char]0x0440 = 'p'; # Cyrillic р → Latin p
        [char]0x0445 = 'x'; # Cyrillic х → Latin x
        [char]0x0456 = 'i'; # Cyrillic і → Latin i
        [char]0x043A = 'k'; # Cyrillic к → Latin k
        [char]0x043C = 'm'; # Cyrillic м → Latin m
        [char]0x0432 = 'v'; # Cyrillic в → Latin v
        [char]0x043D = 'h'; # Cyrillic н → Latin h
        [char]0x0442 = 't'; # Cyrillic т → Latin t
    }
    foreach ($kv in $homoglyphChars.GetEnumerator()) {
        if ($contentStr -match [regex]::Escape($kv.Key)) {
            $errors += "Homoglyph detected: '$($kv.Key)' (looks like '$($kv.Value)') — injection bypass attempt"
            if (-not $script:engramQuiet) { Write-ErrorMsg "Homoglyph character U+$('{0:X4}' -f [int]$kv.Key) (looks like '$($kv.Value)') — possible injection bypass" }
        }
    }
    # Strategy A: normalize whitespace + check raw (catches single-field, multi-space, tab variants)
    $normalized = $contentStr -replace '\s+', ' '
    # Strategy B: join field values (catches split-across-fields: "ignore" in What + "previous" in Why)
    $fieldValueRegex = [regex]'\*\*[^*]+\*\*\s*:\s*((?:(?!\*\*|\n).)*)'
    $allValues = @($fieldValueRegex.Matches($contentStr) | ForEach-Object { $_.Groups[1].Value.Trim() }) -join ' '
    foreach ($pat in $injectionPatterns) {
        if (($normalized -match [regex]::Escape($pat)) -or ($allValues -match [regex]::Escape($pat))) {
            $errors += "Injection pattern detected: '$pat'"
            if (-not $script:engramQuiet) { Write-ErrorMsg "Injection pattern detected in content: '$pat'" }
        }
    }
    # Check topic_key
    if ($topicStr) {
        foreach ($pat in $injectionPatterns) {
            if ($topicStr -match [regex]::Escape($pat)) {
                $errors += "Injection pattern in topic_key: '$pat'"
                if (-not $script:engramQuiet) { Write-ErrorMsg "Injection pattern in topic_key: '$pat'" }
            }
        }
    }

    # --- 3. Extract **fields** ---
    $fieldRegex = [regex]'\*\*([^*]+)\*\*'
    # --- 4. Check canonical fields ---
    $canonical = @("What")
    if ($Strict) { $canonical = @("What", "Why", "Where", "Learned") }

    foreach ($req in $canonical) {
        if ($foundFields -notcontains $req) {
            if ($req -eq "What") {
                $warnings += "Missing required field: **$req**"
                if (-not $script:engramQuiet) { Write-WarnMsg "Missing required field: **$req**" }
            } else {
                $wMsg = "Missing canonical field: **$req** - $typeStr saves richer with full schema"
                $warnings += $wMsg
                if (-not $script:engramQuiet) { Write-WarnMsg $wMsg }
            }
        }
    }

    # --- 5. Type-specific field count check ---
    $typeMinFields = @{
        'bugfix' = 2; 'decision' = 2; 'pattern' = 2
        'learning' = 2; 'discovery' = 1; 'config' = 1
    }
    if ($typeStr -and $typeMinFields.ContainsKey($typeStr)) {
        $minF = $typeMinFields[$typeStr]
        if ($foundFields.Count -lt $minF) {
            $warnings += "Type '$typeStr' expects >=$minF fields (found $($foundFields.Count))"
            if (-not $script:engramQuiet) { Write-WarnMsg "Type '$typeStr' expects >=$minF fields (found $($foundFields.Count))" }
        }
    }

    # --- 6. Fix mode ---
    if ($Fix -and $foundFields -notcontains "What") {
        $contentStr = "**What**: Auto-detected`n$contentStr"
        $foundFields = @($fieldRegex.Matches($contentStr) | ForEach-Object { $_.Groups[1].Value.Trim() })
        if (-not $script:engramQuiet) { "  🔧 Auto-fixed: prepended **What**: Auto-detected" | Out-Host }
    }

    # --- 7. Output ---
    if ($PassThru) {
        if ($errors.Count -gt 0) {
            return $null
        }
        return $Content
    }

    if (-not $script:engramQuiet) {
        if ($errors.Count -eq 0 -and $warnings.Count -eq 0) {
            "  ✅ Engram content valid" | Out-Host
        } elseif ($errors.Count -eq 0) {
            "  ⚠️  Engram content valid with $($warnings.Count) warning(s)" | Out-Host
        } else {
            "  ❌ Engram content invalid: $($errors.Count) error(s)" | Out-Host
        }

        $result = [PSCustomObject]@{
            valid    = ($errors.Count -eq 0)
            errors   = $errors
            warnings = $warnings
            fields   = $foundFields
            fixed    = $Fix -and ($foundFields -contains "What") -and ($Content -is [string]) -and ($contentStr -ne $Content)
            content  = if ($Fix) { $contentStr } else { $null }
        }
        Write-Output $result
    }
    }
}
