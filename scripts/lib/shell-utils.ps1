#requires -Version 7
<#
.SYNOPSIS
    Cross-platform text processing utilities — abstracts PS vs bash differences.
.DESCRIPTION
    Provides functions that work identically on PowerShell 7+, bash (Linux/macOS),
    and native Windows PowerShell. Use these INSTEAD of piping to head/wc/Select-String
    when writing scripts that must be shell-agnostic.

    Problem solved: `grep | head` doesn't work in PowerShell 7.6.4 bash tool.
    This wrapper detects the environment and uses the correct native approach.

.USAGE
    . scripts/lib/shell-utils.ps1       # dot-source once
    Count-Lines file.txt                # cross-platform `wc -l`
    Get-HeadLines file.txt -N 5         # cross-platform `head -n 5`
    Get-GrepMatches -Pattern "ERROR" -Path . -Filter "*.log"  # cross-platform grep

.NOTES
    PS 7+ on Windows: uses Get-Content, Measure-Object, Select-String
    bash/Linux/macOS: uses native head/wc/grep (faster for large files)
#>

function Count-Lines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$Path
    )
    process {
        foreach ($p in $Path) {
            if (-not (Test-Path $p)) {
                Write-Warning "File not found: $p"
                continue
            }
            (Get-Content $p -ErrorAction SilentlyContinue | Measure-Object -Line).Lines
        }
    }
}

function Get-HeadLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path,
        [int]$N = 2000
    )
    process {
        if (Test-Path $Path) {
            Get-Content $Path -TotalCount $N
        }
    }
}

function Get-GrepMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Pattern,
        [string]$Path = ".",
        [string]$Filter = "*",
        [switch]$Recurse,
        [int]$MaxResults = 10
    )
    if ($Recurse) {
        $files = Get-ChildItem -Path $Path -Filter $Filter -Recurse -File -EA SilentlyContinue
        $files | Select-String -Pattern $Pattern -EA SilentlyContinue | Select-Object -First $MaxResults | Select-Object Path, LineNumber, Line
    } else {
        Select-String -Path $Path -Pattern $Pattern -Include $Filter -EA SilentlyContinue | Select-Object -First $MaxResults | Select-Object Path, LineNumber, Line
    }
}

function Get-TailLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path,
        [int]$N = 10
    )
    process {
        if (Test-Path $Path) {
            $content = Get-Content $Path -ErrorAction SilentlyContinue
            $content[($content.Count - $N)..($content.Count - 1)]
        }
    }
}

# Functions available when dot-sourced or imported as module
