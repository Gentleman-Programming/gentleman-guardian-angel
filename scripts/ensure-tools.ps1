#requires -Version 7
[CmdletBinding(SupportsShouldProcess=$true)]
<#
.SYNOPSIS
  Verifica y expone herramientas esenciales en PATH
.DESCRIPTION
  Triple verificación para cada herramienta: (1) existe en PATH (2) --version
  (3) función básica. Dot-source para exponer en sesión actual.
.PARAMETER Quiet
  Suprime output detallado, solo muestra resultado final.
#>

$ErrorActionPreference = 'Stop'

param(
  [switch]$Quiet,
  [switch]$DryRun,
  [switch]$Force
)

Set-StrictMode -Version Latest

$tools = @{
  rg = @{
    label = "ripgrep (busqueda rapida)"
    paths = @(
      "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\BurntSushi.ripgrep.MSVC_Microsoft.Winget.Source_8wekyb3d8bbwe\ripgrep-15.1.0-x86_64-pc-windows-msvc\rg.exe",
      "$env:ProgramFiles\ripgrep\rg.exe"
    )
  }
  sg = @{
    label = "ast-grep (AST structural search)"
    paths = @(
      "$env:APPDATA\npm\sg.ps1",
      "$env:APPDATA\npm\sg.cmd"
    )
  }
  gh = @{
    label = "GitHub CLI"
    paths = @(
      "$env:ProgramFiles\GitHub CLI\gh.exe",
      "${env:ProgramFiles(x86)}\GitHub CLI\gh.exe"
    )
  }
}

$allOk = $true
$script:quietMode = $Quiet

function Write-VerboseOutput($msg) { if (-not $script:quietMode) { Write-Host $msg } }

foreach ($key in $tools.Keys) {
  try {
    $t = $tools[$key]
    $exe = Get-Command $key -ErrorAction SilentlyContinue
    $fullPath = $null

    if ($exe) {
      $fullPath = $exe.Source
    } else {
      foreach ($p in $t.paths) {
        if (Test-Path $p) {
          $fullPath = $p
          break
        }
      }
    }

    if ($fullPath) {
      $parent = Split-Path $fullPath -Parent
      if ($parent -notin ($env:Path -split ';')) {
        $env:Path = "${parent};$env:Path"
      }
      Write-VerboseOutput "[$key] OK - $($t.label)"
      Write-VerboseOutput "       $fullPath"

      # V1: --version (check output, not exit code — PS scripts don't set LASTEXITCODE)
      $ver = & $fullPath --version 2>&1 | Select-Object -First 1
      if ($ver) {
        Write-VerboseOutput "       version: $ver"
      } else {
        Write-VerboseOutput "       version: FAIL (no output)"
        $allOk = $false
      }

      # V2: basic function (rg only — native binary)
      if ($key -eq 'rg') {
        $testFile = Join-Path (Join-Path $env:TEMP "ensure-tools-test.txt") "hello world" | Set-Content $testFile -Encoding utf8 -ErrorAction Stop
        $null = & $fullPath "hello" $testFile 2>$null
        if ($LASTEXITCODE -eq 0) {
          Write-VerboseOutput "       search: OK"
        } else {
          Write-VerboseOutput "       search: FAIL"
          $allOk = $false
        }
        Remove-Item $testFile -Force -ErrorAction Stop
      }
    } else {
      Write-VerboseOutput "[$key] NOT FOUND - $($t.label)"
      $allOk = $false
    }
  } catch {
    Write-Error "Tool check failed for $key`: $_"
    $allOk = $false
  }
}

if ($allOk) {
  Write-VerboseOutput "ALL TOOLS OK"
} else {
  Write-VerboseOutput "SOME TOOLS MISSING"
}

return $allOk
