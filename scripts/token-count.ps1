#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Cuenta tokens aproximados en archivos (default: 3.5 chars = 1 token)
.DESCRIPTION
  Estimación rápida de tokens usando heurística chars/Divisor. Soporta múltiples
  archivos, directorios y búsqueda recursiva.
.PARAMETER Path
  Archivo(s) específico(s) a contar.
.PARAMETER Dir
  Directorio a escanear (default: skills/).
.PARAMETER Recurse
  Buscar recursivamente en subdirectorios.
.PARAMETER Divisor
  Heurística chars por token (default: 3.5 — alineado con tokenize-all.ps1 y
  la métrica TokenEstimate de benchmark.ps1).
#>

param(
    [switch]$Quiet,
  [string[]]$Path = @(),
  [string]$Dir = "",
    [switch]$Recurse,
  [double]$Divisor = 3.5
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Rough token counter: ~3.5 chars per token for code/text
function Get-TokenCount {
  param([string]$Content, [double]$Divisor = 3.5)
  # Strip whitespace, count ~Divisor chars/token
  $clean = $Content -replace '\s+', ' '
  return [math]::Max(1, [int]($clean.Length / $Divisor))
}

try {
  $targets = @()

  if ($Dir) {
    $targets = try { Get-ChildItem -LiteralPath $Dir -File -Recurse:$Recurse -ErrorAction Stop } catch { Write-Warning "Could not enumerate path '$Dir': $_"; @() }
  } elseif ($Path.Count -gt 0) {
    $targets = $Path | ForEach-Object {
      if (Test-Path $_ -PathType Container) {
        try { Get-ChildItem -LiteralPath $_ -File -Recurse -ErrorAction Stop } catch { Write-Warning "Could not enumerate path '$_': $_"; @() }
      } else {
        Get-Item $_
      }
    }
  } else {
    $targets = try { Get-ChildItem -LiteralPath "." -File -ErrorAction Stop } catch { Write-Warning "Could not enumerate path: $_"; @() }
  }

  $grandTotal = 0
  $results = @()
  $maxNameLen = 0

  foreach ($f in $targets) {
    $content = try { Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop } catch { Write-Warning "Could not read file '$($f.FullName)': $_"; $null }
    if (-not $content) { continue }
    $tokens = Get-TokenCount $content $Divisor
    $results += [PSCustomObject]@{
      File = $f.FullName
      Tokens = $tokens
      SizeKB = [math]::Round($f.Length / 1KB, 1)
    }
    $grandTotal += $tokens
    if ($f.FullName.Length -gt $maxNameLen) { $maxNameLen = $f.FullName.Length }
  }

  # Sort by tokens descending
  $results = $results | Sort-Object Tokens -Descending

  # ponytail: guard informational display — data output is the return value
  if (-not $Quiet) {
    Write-Host "=== TOKEN COUNT ===" -ForegroundColor Cyan
    $results | ForEach-Object {
      Write-Host ("  {0,-$($maxNameLen+2)} {1,7} tokens  ({2,6} KB)") -f $_.File, $_.Tokens, $_.SizeKB
    }
    Write-Host ("  {0,-$($maxNameLen+2)} {1,7} tokens  TOTAL") -f "---", $grandTotal -ForegroundColor Green
  }

  return $grandTotal
} catch {
  Write-Error "Script failed: $_"
  exit 1
}
