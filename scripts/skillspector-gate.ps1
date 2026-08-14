#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
    SkillSpector security gate for agent skills. Scans .agents/skills/
  for vulnerabilities using NVIDIA SkillSpector (static analysis only).
.DESCRIPTION
  Optional gate in the !ship pipeline. Tries skillspector CLI first,
  falls back to Docker image, then gracefully skips if unavailable.
  Self-modification findings (RA1) in dreaming/immune-system skills
  are intentional and do not block the gate.

  Scans each skill independently (--recursive): the directory aggregates
  into a single 100/100 score when scanned as one unit, which would
  always fail the gate. Per-skill scores reflect real per-skill risk.

.PARAMETER SkillsPath
  Path to skills directory (default: .agents/skills).
.PARAMETER FailOnRisk
  Exit code 1 if any skill risk score exceeds this threshold (0-100, default: 100).
  Default 100 accepts self-modification findings (by design).
  Set lower for strict CI: skillspector-gate.ps1 -FailOnRisk 50
.PARAMETER DockerImage
  Docker image name when using Docker fallback (default: skillspector:v2.5.0,
  pinned to match the CLI version — image/CLI drift breaks the JSON-to-file
  output contract and the gate fails closed).
.PARAMETER Strict
  Exit with code 1 when scanner is unavailable or risk exceeds threshold.
  Required for CI: skillspector-gate.ps1 -Strict -FailOnRisk 50
.PARAMETER Quiet
  Suppress progress output; only warnings and errors are printed.
#>
param(
    [string]$SkillsPath = ".agents/skills",
    [int]$FailOnRisk = 100,
    [string]$DockerImage = "skillspector:v2.5.0",
    [switch]$Strict,
    [switch]$Quiet
)
Set-StrictMode -Version Latest

$ErrorActionPreference = "Stop"
$scriptName = "skillspector-gate"
$script:RiskExceeded = $false
$script:ScanFailed = $false

# Resolve full path
$resolvedPath = Resolve-Path $SkillsPath -ErrorAction SilentlyContinue
if (-not $resolvedPath) {
    Write-Warning "${scriptName}: Path '$SkillsPath' not found"
    if ($Strict) { exit 1 }
    exit 0
}

function Write-Report {
    param($report)
    if (-not $report) { if(-not $Quiet) { Write-Host "   ⚪ No report to parse" }; return }

    # Multi-skill report (--recursive): evaluate EACH skill independently.
    # The consolidated object carries skills[] with per-skill risk_assessment.
    if ($report.multi_skill -and $report.skills) {
        $overThreshold = @()
        foreach ($s in $report.skills) {
            $realFindings = @($s.issues | Where-Object { $_.id -ne "RA1" })
            $realCount = $realFindings.Count
            if ($realCount -gt 0 -and $s.risk_assessment.score -ge $FailOnRisk) {
                $overThreshold += [PSCustomObject]@{
                    Skill    = $s.skill.name
                    Score    = $s.risk_assessment.score
                    Severity = $s.risk_assessment.severity
                    Findings = $realCount
                }
            }
        }
        $scannedCount = [int]$report.skill_count
        if(-not $Quiet) {
            Write-Host "   Skills scanned: $scannedCount | Max risk: $($report.max_risk_score)/100"
        }
        if ($overThreshold.Count -gt 0) {
            Write-Warning "⚠️ $($overThreshold.Count) skill(s) exceed threshold ${FailOnRisk}:"
            foreach ($o in $overThreshold) {
                Write-Warning "   - $($o.Skill): risk $($o.Score) ($($o.Severity)), $($o.Findings) non-RA1 finding(s)"
            }
            $script:RiskExceeded = $true
        } elseif(-not $Quiet) {
            Write-Host "   ✅ All skills clean (non-RA1 risk < $FailOnRisk)"
        }
        return
    }

    # Single-skill report (legacy path)
    $riskScore = $report.risk_assessment.score
    $severity = $report.risk_assessment.severity
    $findingsCount = ($report.issues | Measure-Object).Count

    if(-not $Quiet) {
      Write-Host "   Risk score: $riskScore/100 ($severity)"
      Write-Host "   Findings: $findingsCount"
    }

    if ($findingsCount -gt 0 -and $report.issues) {
        foreach ($f in $report.issues) {
            $row = [PSCustomObject]@{
                ID       = $f.id
                Category = $f.category
                Severity = $f.severity
                File     = $f.location.file
                Line     = $f.location.start_line
                Confidence = "{0:P0}" -f $f.confidence
            }
            if(-not $Quiet) { $row | Format-Table -AutoSize | Out-Host }
        }
    }

    # Filter out RA1 (self-modification) — these are by design in system skills
    $realFindings = $report.issues | Where-Object { $_.id -ne "RA1" }
    $realCount = ($realFindings | Measure-Object).Count

    if ($realCount -eq 0) {
        if(-not $Quiet) { Write-Host "   ✅ Only RA1 findings (self-modification by design) — clean" }
        return
    }

    if ($riskScore -ge $FailOnRisk) {
        Write-Warning "⚠️ Risk score $riskScore exceeds threshold $FailOnRisk ($realCount non-RA1 findings)"
        $script:RiskExceeded = $true
    }

    if ($riskScore -ge 30) {
        if(-not $Quiet) { Write-Host "   → Revisar hallazgos antes de commit. RA1 ignorados por diseño." }
    } else {
        if(-not $Quiet) { Write-Host "   ✅ Skills clean (non-RA1 risk < threshold)" }
    }
}

function Invoke-Scan {
    param([string]$Runner, [string]$JsonOutput)
    if ([string]::IsNullOrWhiteSpace($JsonOutput)) {
        Write-Warning "${scriptName}: Empty output from $Runner — gate cannot evaluate"
        $script:ScanFailed = $true
        return
    }
    # Strip warning lines before JSON (SkillSpector prints warnings to stdout)
    $jsonStart = $JsonOutput.IndexOf('{')
    if ($jsonStart -ge 0) {
        $JsonOutput = $JsonOutput.Substring($jsonStart)
    }
    try {
        $report = $JsonOutput | ConvertFrom-Json
        Write-Report $report
    } catch {
        Write-Warning "${scriptName}: Could not parse $Runner output — gate cannot evaluate"
        $script:ScanFailed = $true
        if(-not $Quiet) {
          Write-Host "Raw output (first 500 chars):"
          Write-Host ($JsonOutput.Substring(0, [Math]::Min(500, $JsonOutput.Length)))
        }
    }
}

# --- Try CLI ---
$sp = Get-Command "skillspector" -ErrorAction SilentlyContinue
if ($sp) {
    if(-not $Quiet) { Write-Host "🔍 [CLI] Scanning skills with SkillSpector (static only)..." }
    # --recursive: per-skill JSON goes to --output file, NOT stdout (v2.5.0 quirk)
    # Atomic exclusive temp name — PID-predictable names are a symlink/TOCTOU vector
    $tempJson = [IO.Path]::GetTempFileName()
    try {
        $null = & skillspector scan $resolvedPath --recursive --no-llm --format json --output $tempJson 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "${scriptName}: skillspector CLI exited with code $LASTEXITCODE — gate cannot evaluate"
            $script:ScanFailed = $true
        }
        $jsonOutput = if (Test-Path $tempJson) { Get-Content $tempJson -Raw } else { "" }
    } finally {
        # Temp file we created ourselves — .NET Delete avoids cmdlet safety-ceremony
        if (Test-Path $tempJson) { [System.IO.File]::Delete($tempJson) }
    }
    Invoke-Scan -Runner "CLI" -JsonOutput $jsonOutput
    if ($Strict -and ($script:RiskExceeded -or $script:ScanFailed)) { exit 1 }
    exit 0
}

# --- Try Docker ---
$dockerOk = $false
try {
    $null = docker ps 2>&1
    if ($LASTEXITCODE -eq 0) { $dockerOk = $true }
} catch { Write-Debug "Docker check failed: $_" }

if ($dockerOk) {
    if(-not $Quiet) { Write-Host "🔍 [Docker] Scanning skills with SkillSpector (static only)..." }
    $hostPath = (Split-Path $resolvedPath.Path -Parent) -replace '\\', '/'
    $scanTarget = "/scan/$(Split-Path $resolvedPath.Path -Leaf)"
    # Temp file OUTSIDE the repo tree (atomic name); never write reports into the working copy
    $tempJson = [IO.Path]::GetTempFileName()
    $tempJsonName = Split-Path $tempJson -Leaf
    $tempDirHost = (Split-Path $tempJson -Parent) -replace '\\', '/'
    try {
        # Skills dir mounted READ-ONLY so the container cannot write back into the repo
        docker run --rm -v "${hostPath}:/scan:ro" -v "${tempDirHost}:/gateout" $DockerImage scan $scanTarget --recursive --no-llm --format json --output "/gateout/$tempJsonName" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "${scriptName}: docker run exited with code $LASTEXITCODE — gate cannot evaluate"
            $script:ScanFailed = $true
        }
        $jsonOutput = if (Test-Path $tempJson) { Get-Content $tempJson -Raw } else { "" }
    } finally {
        # Container may leave a root-owned file (Linux hosts) — delete best-effort only
        if (Test-Path $tempJson) { try { [System.IO.File]::Delete($tempJson) } catch { Write-Debug "${scriptName}: temp cleanup: $($_.Exception.Message)" } }
    }
    Invoke-Scan -Runner "Docker" -JsonOutput $jsonOutput
    if ($Strict -and ($script:RiskExceeded -or $script:ScanFailed)) { exit 1 }
    exit 0
}

# --- Neither available ---
if(-not $Quiet) {
  Write-Host "⚪ SkillSpector not installed — skipping"
  Write-Host "   CLI: pip install git+https://github.com/NVIDIA/SkillSpector.git@v2.5.0"
  Write-Host "   Docker: docker build -t skillspector:v2.5.0 . (from repo clone)"
}
if ($Strict) {
    Write-Warning "⚠️ SkillSpector unavailable in strict mode — failing gate"
    exit 1
}
exit 0
