#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pipeline de análisis multi-proyecto — gather + report + save to docs/investigacion/
.DESCRIPTION
    Escanea un proyecto: git status, estructura, score, dependencias.
    Genera reporte JSON y lo deja listo para análisis del agente.
    Modos:
      - gather   : recolecta datos → stdout JSON + {proyecto}/docs/investigacion/_data.json
      - report   : lee _data.json y genera markdown de análisis
      - full     : gather + report (default)
.PARAMETER ProjectPath
    Ruta al proyecto a analizar. Requerido.
.PARAMETER Mode
    Modo de operación: gather, report, full (default)
.PARAMETER OutDir
    Directorio de salida (default: {project}/docs/investigacion/)
.EXAMPLE
    .\pipeline-analyze.ps1 -ProjectPath D:\opencode
    .\pipeline-analyze.ps1 -ProjectPath D:\arturo -Mode gather
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectPath,
    [ValidateSet('gather','report','full')]
    [string]$Mode = 'full',
    [string]$OutDir = ''
)
Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'

# ── Resolve paths ──────────────────────────────────────────────
$ProjectPath = Resolve-Path $ProjectPath -ErrorAction Stop
$projectName = Split-Path $ProjectPath -Leaf
if (-not $OutDir) { $OutDir = Join-Path $ProjectPath 'docs\investigacion' }
$dataFile = Join-Path $OutDir '_data.json'
$reportFile = Join-Path $OutDir "$(Get-Date -Format 'yyyy-MM-dd')-analisis.md"

# Ensure out dir
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

# ── Helper functions ───────────────────────────────────────────
function Get-GitInfo {
    param([string]$Path)
    $gitDir = Join-Path $Path '.git'
    if (-not (Test-Path $gitDir)) { return @{ isRepo = $false } }

    Push-Location $Path
    try {
        $branch = git branch --show-current 2>$null
        $status = git status --short 2>$null
        $log = git log --oneline -10 2>$null
        $modifiedCount = if ($status) { ($status -split "`n").Count } else { 0 }
        $hasUpstream = git remote -v 2>$null -match 'origin'
        return @{
            isRepo = $true
            branch = $branch
            modified = @($status)
            modifiedCount = $modifiedCount
            recentCommits = @($log)
            hasUpstream = [bool]$hasUpstream
        }
    } finally { Pop-Location }
}

function Get-ProjectScore {
    param([string]$Path)
    $scoreFile = Join-Path $Path '.project.json'
    if (Test-Path $scoreFile) {
        try {
            $raw = Get-Content $scoreFile -Raw -Encoding UTF8
            $json = $raw | ConvertFrom-Json
            return @{
                hasScore = $true
                score = $json.score
                raw = $json
            }
        } catch { return @{ hasScore = $false; error = $_.Exception.Message } }
    }
    return @{ hasScore = $false }
}

function Get-Structure {
    param([string]$Path)
    $items = Get-ChildItem $Path -Depth 0
    $dirs = @($items | Where-Object PSIsContainer | Select-Object -ExpandProperty Name)
    $rootFiles = @($items | Where-Object { -not $_.PSIsContainer } | Select-Object Name, Length)
    return @{
        directories = $dirs
        rootFiles = $rootFiles
        hasPackageJson = Test-Path (Join-Path $Path 'package.json')
        hasPyprojectToml = Test-Path (Join-Path $Path 'pyproject.toml')
        hasDockerCompose = Test-Path (Join-Path $Path 'docker-compose.yml')
        hasGentlemanConfig = (Test-Path (Join-Path $Path 'AGENTS.md')) -or (Test-Path (Join-Path $Path '.agents'))
    }
}

function Get-ProjectType {
    param([hashtable]$Structure)
    if ($Structure.hasPyprojectToml) { return 'python' }
    if ($Structure.hasPackageJson) { return 'node' }
    if ($Structure.hasDockerCompose) { return 'docker' }
    # heuristic
    $dirs = $Structure.directories
    if ($dirs -contains 'src' -and $dirs -contains 'tests') { return 'python' }
    if ($dirs -contains 'apps' -and $dirs -contains 'packages') { return 'monorepo-node' }
    if ($dirs -contains 'backend' -and $dirs -contains 'frontend') { return 'fullstack' }
    return 'unknown'
}

# ── GATHER ─────────────────────────────────────────────────────
$data = @{
    project = $projectName
    path = $ProjectPath
    analyzedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    git = Get-GitInfo $ProjectPath
    score = Get-ProjectScore $ProjectPath
    structure = Get-Structure $ProjectPath
    type = $null
}
$data.type = Get-ProjectType $data.structure

if ($Mode -in 'gather','full') {
    $data | ConvertTo-Json -Depth 5 | Set-Content $dataFile -Encoding UTF8
    Write-Host "📦 Data gathered → $dataFile"
}

# ── REPORT ─────────────────────────────────────────────────────
if ($Mode -in 'report','full') {
    if (-not (Test-Path $dataFile)) { Write-Error "No data file. Run gather first."; exit 1 }
    $d = Get-Content $dataFile -Raw -Encoding UTF8 | ConvertFrom-Json

    $lines = @()
    $lines += "# Análisis: $($d.project)"
    $lines += ""
    $lines += "**Fecha**: $($d.analyzedAt) · **Tipo**: $($d.type)"
    $lines += ""

    # Git
    if ($d.git.isRepo) {
        $lines += "## Git"
        $lines += "- Rama: **$($d.git.branch)**"
        $lines += "- Cambios sin commit: **$($d.git.modifiedCount)**"
        if ($d.git.modifiedCount -gt 0) {
            $lines += "- Archivos modificados:"
            foreach ($m in $d.git.modified) { $lines += "  - `$m" }
        }
        $lines += "- Commits recientes:"
        foreach ($c in $d.git.recentCommits) { $lines += "  - `$c" }
        $lines += ""
    } else {
        $lines += "## Git"
        $lines += "- **No es repo git**"
        $lines += ""
    }

    # Score
    if ($d.score.hasScore) {
        $lines += "## Score"
        $lines += "- **$($d.score.score)/10**"
        if ($d.score.raw.dimensions) {
            foreach ($dim in $d.score.raw.dimensions.PSObject.Properties) {
                $lines += "- $($dim.Name): $($dim.Value)"
            }
        }
        $lines += ""
    }

    # Structure
    $lines += "## Estructura"
    $lines += "- Directorios: $($d.structure.directories -join ', ')"
    $lines += "- Gentleman config: $($d.structure.hasGentlemanConfig)"
    $lines += ""

    $lines += "---"
    $lines += "*Generado por pipeline-analyze.ps1 · @gentleman-vMK*"

    $report = $lines -join "`n"
    $report | Set-Content $reportFile -Encoding UTF8
    Write-Host "📝 Report generated → $reportFile"
}

Write-Host "✅ pipeline-analyze complete for $projectName"
