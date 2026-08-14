#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    Budget constraint checker — validates tool-call, step, and time limits
    per task, per the Budget Constraints protocol.

.DESCRIPTION
    Encapsulates the four hard limits from _core-behavior-gp.md §"Budget
    Constraints (MANDATORY for all executors)":
      1. Tool calls: Max 25 per task
      2. Loop prevention: same tool + same args twice → abort
      3. Time: Max 5 min (300s) wall-clock per task
      4. Step cap: Max 15 reasoning steps per task

    Violation of any budget = task failure. Call this from the orchestrator
    after each reasoning round to check remaining budget, or use the
    -LoopCheck parameter to detect repeated tool+args.

.PARAMETER ToolCalls
    Current tool call count for this task.

.PARAMETER Steps
    Current reasoning step count for this task.

.PARAMETER ElapsedSeconds
    Elapsed wall-clock time in seconds.

.PARAMETER ToolName
    Name of the tool being called (for loop detection).

.PARAMETER ToolArgs
    Arguments hash for the tool (for loop detection).

.PARAMETER Json
    Emit machine-readable JSON.

.EXAMPLE
    # Check if we're within budget
    .\scripts\check-budget.ps1 -ToolCalls 12 -Steps 7 -ElapsedSeconds 90
    # → "OK  Budget: 12/25 tool calls, 7/15 steps, 90s/300s"

    # Detect loop (same tool + args as last call)
    .\scripts\check-budget.ps1 -ToolName "grep" -ToolArgs @{pattern="auth";path="."} -LastToolName "grep" -LastToolArgs @{pattern="auth";path="."}
    # → "ABORT  Circuit breaker: repeated tool call (grep) with same args"
#>
param(
    [int]$ToolCalls = 0,
    [int]$Steps = 0,
    [int]$ElapsedSeconds = 0,
    [int]$ToolCallLimit = 25,
    [int]$StepLimit = 15,
    [int]$TimeLimitSeconds = 300,
    [string]$ToolName = "",
    [string]$LastToolName = "",
    [hashtable]$ToolArgs = $null,
    [hashtable]$LastToolArgs = $null,
    [switch]$Json
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$violations = @()

# --- 1. Tool call budget ---
if ($ToolCalls -gt $ToolCallLimit) {
    $violations += "tool-calls: $ToolCalls exceeds limit $ToolCallLimit"
}

# --- 2. Step budget ---
if ($Steps -gt $StepLimit) {
    $violations += "steps: $Steps exceeds limit $StepLimit"
}

# --- 3. Time budget ---
if ($ElapsedSeconds -gt $TimeLimitSeconds) {
    $violations += "time: $ElapsedSeconds exceeds limit $TimeLimitSeconds"
}

# --- 4. Loop prevention (same tool + same args twice in a row) ---
$loopDetected = $false
if ($ToolName -and $LastToolName -and $ToolArgs -and $LastToolArgs -and
    $ToolName -eq $LastToolName) {
    $currentArgs = ($ToolArgs.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '|'
    $lastArgs = ($LastToolArgs.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '|'
    if ($currentArgs -eq $lastArgs) {
        $loopDetected = $true
        $violations += "loop: repeated tool '$ToolName' with identical args"
    }
}

$passed = $violations.Count -eq 0 -and -not $loopDetected

if ($Json) {
    [PSCustomObject]@{
        passed          = $passed
        toolCalls       = $ToolCalls
        toolCallLimit   = $ToolCallLimit
        steps           = $Steps
        stepLimit       = $StepLimit
        elapsedSeconds  = $ElapsedSeconds
        timeLimit       = $TimeLimitSeconds
        loopDetected    = $loopDetected
        violations      = $violations
        } | ConvertTo-Json -Compress
        $ec = if ($passed) { 0 } else { 1 }
        exit $ec
    }

# Human-readable
if ($passed) {
    Write-Output "OK   Budget: $ToolCalls/$ToolCallLimit tool calls, $Steps/$StepLimit steps, ${ElapsedSeconds}s/$TimeLimitSeconds"
} else {
    Write-Output "FAIL Budget exceeded:"
    $violations | ForEach-Object { Write-Output "   X  $_" }
    Write-Output "     Violation of any budget = task failure"
}
$ec = if ($passed) { 0 } else { 1 }
exit $ec
