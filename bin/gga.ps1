# ============================================================================
# Gentleman Guardian Angel - PowerShell CLI
# ============================================================================
# Provider-agnostic code review using AI
# ============================================================================

param(
    [Parameter(Position = 0)]
    [string]$Command = "",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs = @()
)

$ErrorActionPreference = "Stop"

# Parse command and arguments
$allArgs = @($Command) + @($RemainingArgs)
$allArgs = @($allArgs | Where-Object { $_ -ne "" -and $_ -ne $null })
$cmd = if ($allArgs.Count -gt 0) { $allArgs[0] } else { "" }

$VERSION = "2.7.0"
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Determine lib directory - check multiple locations
$UserHome = [System.Environment]::GetFolderPath('UserProfile')
$InstalledLibDir = Join-Path $UserHome ".local\share\gga\lib"
$DevLibDir = Join-Path $ScriptDir "..\lib"

if (Test-Path $InstalledLibDir) {
    $LibDir = $InstalledLibDir
} else {
    $LibDir = $DevLibDir
}

. "$LibDir\providers.ps1"
. "$LibDir\cache.ps1"
. "$LibDir\pr_mode.ps1"

$script:PROVIDER = ""
$script:FILE_PATTERNS = "*"
$script:EXCLUDE_PATTERNS = ""
$script:RULES_FILE = "AGENTS.md"
$script:STRICT_MODE = $true
$script:TIMEOUT = 300
$script:PR_BASE_BRANCH = ""

function Write-Color {
    param(
        [string]$Message, 
        [string]$Color = "White"
    )
    $ColorMap = @{
        "RED" = "Red"
        "GREEN" = "Green"
        "YELLOW" = "Yellow"
        "BLUE" = "Blue"
        "CYAN" = "Cyan"
        "BOLD" = "White"
    }
    $fg = if ($ColorMap.ContainsKey($Color)) { $ColorMap[$Color] } else { $Color }
    Write-Host $Message -ForegroundColor $fg
}

function Write-Banner {
    Write-Color -Message "" -Color "Cyan"
    Write-Color -Message "============================================================" -Color "Cyan"
    Write-Color -Message "  Gentleman Guardian Angel v$VERSION" -Color "Cyan"
    Write-Color -Message "  Provider-agnostic code review using AI" -Color "Cyan"
    Write-Color -Message "============================================================" -Color "Cyan"
    Write-Color -Message "" -Color "Cyan"
}

function Get-Help {
    Write-Banner
    Write-Color -Message "USAGE:" -Color "White"
    Write-Host "  gga <command> [options]"
    Write-Host ""
    Write-Color -Message "COMMANDS:" -Color "White"
    Write-Host "  run [--no-cache]  Run code review on staged files"
    Write-Host "  install           Install git pre-commit hook (default)"
    Write-Host "  install --commit-msg"
    Write-Host "                    Install git commit-msg hook"
    Write-Host "  uninstall         Remove git hooks from current repo"
    Write-Host "  config            Show current configuration"
    Write-Host "  init              Create a sample .gga config file"
    Write-Host "  cache clear       Clear cache for current project"
    Write-Host "  cache clear-all   Clear all cached data"
    Write-Host "  cache status      Show cache status"
    Write-Host "  help              Show this help message"
    Write-Host "  version           Show version"
    Write-Host ""
    Write-Color -Message "RUN OPTIONS:" -Color "White"
    Write-Host "  --no-cache        Force review all files, ignoring cache"
    Write-Host "  --ci              CI mode: review files changed in last commit"
    Write-Host "  --pr-mode         PR mode: review all files changed in PR"
    Write-Host "  --diff-only       With --pr-mode: send only diffs"
    Write-Host "  --commit-msg-file Path to commit message file (commit-msg hook)"
    Write-Host ""
    Write-Color -Message "CONFIGURATION:" -Color "White"
    Write-Host "  Create a .gga file in your project root or"
    Write-Host "  `$env:USERPROFILE\.config\gga\.gga for global settings."
    Write-Host ""
    Write-Color -Message "CONFIG OPTIONS:" -Color "White"
    Write-Host "  PROVIDER           AI provider (claude, gemini, codex, opencode,"
    Write-Host "                     ollama:<model>, lmstudio[:model], github:<model>)"
    Write-Host "  FILE_PATTERNS      File patterns to review (default: *)"
    Write-Host "  EXCLUDE_PATTERNS   Patterns to exclude"
    Write-Host "  RULES_FILE         File with review rules (default: AGENTS.md)"
    Write-Host "  STRICT_MODE        Fail on ambiguous AI response (default: true)"
    Write-Host "  TIMEOUT            Max seconds for AI response (default: 300)"
    Write-Host ""
}

function Get-Version {
    Write-Host "gga v$VERSION"
}

function Write-TextFileNoBom {
    param(
        [string]$Path,
        [string]$Content
    )

    $normalizedContent = $Content -replace "`r`n", "`n"
    $resolvedPath = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    } else {
        Join-Path (Get-Location) $Path
    }
    $parentDir = Split-Path -Path $resolvedPath -Parent
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($resolvedPath, $normalizedContent, (New-Object System.Text.UTF8Encoding($false)))
}

function Load-Config {
    $script:PROVIDER = ""
    $script:FILE_PATTERNS = "*"
    $script:EXCLUDE_PATTERNS = ""
    $script:RULES_FILE = "AGENTS.md"
    $script:STRICT_MODE = $true
    $script:TIMEOUT = 300
    $script:PR_BASE_BRANCH = ""

    function Set-ConfigValue {
        param(
            [string]$Key,
            [string]$Value
        )

        $normalizedKey = $Key.Trim().ToUpperInvariant()
        $normalizedValue = $Value.Trim()

        if (
            ($normalizedValue.StartsWith('"') -and $normalizedValue.EndsWith('"')) -or
            ($normalizedValue.StartsWith("'") -and $normalizedValue.EndsWith("'"))
        ) {
            $normalizedValue = $normalizedValue.Substring(1, $normalizedValue.Length - 2)
        }

        switch ($normalizedKey) {
            "PROVIDER" { $script:PROVIDER = $normalizedValue }
            "FILE_PATTERNS" { $script:FILE_PATTERNS = $normalizedValue }
            "EXCLUDE_PATTERNS" { $script:EXCLUDE_PATTERNS = $normalizedValue }
            "RULES_FILE" { $script:RULES_FILE = $normalizedValue }
            "STRICT_MODE" { $script:STRICT_MODE = ($normalizedValue -match '^(?i:true|1|yes|y)$') }
            "TIMEOUT" {
                $timeoutValue = 0
                if ([int]::TryParse($normalizedValue, [ref]$timeoutValue) -and $timeoutValue -gt 0) {
                    $script:TIMEOUT = $timeoutValue
                }
            }
            "PR_BASE_BRANCH" { $script:PR_BASE_BRANCH = $normalizedValue }
        }
    }

    function Import-ConfigFile {
        param([string]$Path)

        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            return
        }

        Get-Content -Path $Path | ForEach-Object {
            $line = $_.Trim()
            if (-not $line -or $line.StartsWith("#")) {
                return
            }
            $separatorIndex = $line.IndexOf("=")
            if ($separatorIndex -lt 1) {
                return
            }
            $key = $line.Substring(0, $separatorIndex).Trim()
            $value = $line.Substring($separatorIndex + 1).Trim()
            Set-ConfigValue -Key $key -Value $value
        }
    }

    $globalConfig = Join-Path $env:USERPROFILE ".config\gga\config"
    $globalConfigAlt = Join-Path $env:USERPROFILE ".config\gga\.gga"
    Import-ConfigFile -Path $globalConfig
    Import-ConfigFile -Path $globalConfigAlt

    $projectConfig = ".gga"
    Import-ConfigFile -Path $projectConfig

    if ($env:GGA_PROVIDER) { $script:PROVIDER = $env:GGA_PROVIDER }
    if ($env:GGA_TIMEOUT) {
        $envTimeout = 0
        if ([int]::TryParse($env:GGA_TIMEOUT, [ref]$envTimeout) -and $envTimeout -gt 0) {
            $script:TIMEOUT = $envTimeout
        }
    }
}

function Get-ConfigFilesForCache {
    $globalConfig = Join-Path $env:USERPROFILE ".config\gga\config"
    $globalConfigAlt = Join-Path $env:USERPROFILE ".config\gga\.gga"
    return @(".gga", $globalConfig, $globalConfigAlt)
}

function Show-Config {
    Write-Banner
    Load-Config

    Write-Color -Message "Current Configuration:" -Color "White"
    Write-Host ""

    $globalConfig = Join-Path $env:USERPROFILE ".config\gga\config"
    $globalConfigAlt = Join-Path $env:USERPROFILE ".config\gga\.gga"
    $projectConfig = ".gga"

    Write-Color -Message "Config Files:" -Color "White"
    if (Test-Path -Path $globalConfig -PathType Leaf) {
        Write-Color "  Global:  $globalConfig" "Green"
    } elseif (Test-Path -Path $globalConfigAlt -PathType Leaf) {
        Write-Color "  Global:  $globalConfigAlt" "Green"
    } else {
        Write-Color "  Global:  Not found" "Yellow"
    }
    if (Test-Path -Path $projectConfig -PathType Leaf) {
        Write-Color "  Project: $projectConfig" "Green"
    } else {
        Write-Color "  Project: Not found" "Yellow"
    }
    Write-Host ""

    Write-Color -Message "Values:" -Color "White"
    if ($script:PROVIDER) {
        Write-Color "  PROVIDER:          $($script:PROVIDER)" "Green"
    } else {
        Write-Color "  PROVIDER:          Not configured" "Red"
    }
    Write-Color "  FILE_PATTERNS:     $($script:FILE_PATTERNS)" "Cyan"
    if ($script:EXCLUDE_PATTERNS) {
        Write-Color "  EXCLUDE_PATTERNS:  $($script:EXCLUDE_PATTERNS)" "Cyan"
    } else {
        Write-Color "  EXCLUDE_PATTERNS:  None" "Yellow"
    }
    Write-Color "  RULES_FILE:        $($script:RULES_FILE)" "Cyan"
    Write-Color "  STRICT_MODE:       $($script:STRICT_MODE)" "Cyan"
    Write-Color "  TIMEOUT:           $($script:TIMEOUT)s" "Cyan"
    if ($script:PR_BASE_BRANCH) {
        Write-Color "  PR_BASE_BRANCH:    $($script:PR_BASE_BRANCH)" "Cyan"
    } else {
        Write-Color "  PR_BASE_BRANCH:    auto-detect" "Yellow"
    }
    Write-Host ""

    if (Test-Path $script:RULES_FILE) {
        Write-Color "Rules File: Found" "Green"
    } else {
        Write-Color "Rules File: Not found ($($script:RULES_FILE))" "Red"
    }
    Write-Host ""
}

function Initialize-Config {
    Write-Banner

    $projectConfig = ".gga"

    if (Test-Path $projectConfig) {
        Write-Color "Config file already exists: $projectConfig" "Yellow"
        $confirm = Read-Host "Overwrite? (y/N)"
        if ($confirm -ne "y" -and $confirm -ne "Y") {
            Write-Host "Aborted."
            exit 0
        }
    }

    @"
# Gentleman Guardian Angel Configuration
# https://github.com/your-org/gga

# AI Provider (required)
# Options: claude, gemini, codex, opencode, ollama:<model>, lmstudio[:model], github:<model>
PROVIDER="claude"

# File patterns to include in review (comma-separated)
FILE_PATTERNS="*.ts,*.tsx,*.js,*.jsx"

# File patterns to exclude from review (comma-separated)
EXCLUDE_PATTERNS="*.test.ts,*.spec.ts,*.test.tsx,*.spec.tsx,*.d.ts"

# File containing code review rules
RULES_FILE="AGENTS.md"

# Strict mode: fail if AI response is ambiguous
STRICT_MODE="true"

# Timeout in seconds for AI provider response
TIMEOUT="300"

# Base branch for --pr-mode (auto-detects main/master/develop if empty)
# PR_BASE_BRANCH="main"
"@ | Out-File -FilePath $projectConfig -Encoding utf8

    Write-Color "Created config file: $projectConfig" "Green"
    Write-Host ""
    Write-Color "Next steps:" "Blue"
    Write-Host "  1. Edit $projectConfig to set your preferred provider"
    Write-Host "  2. Create $($script:RULES_FILE) with your coding standards"
    Write-Host "  3. Run: gga install"
    Write-Host ""
}

function Install-Hook {
    param([string]$HookType = "pre-commit")

    Write-Banner

    $gitRoot = git rev-parse --show-toplevel 2>$null
    if (-not $gitRoot) {
        Write-Color "Not a git repository" "Red"
        exit 1
    }

    $hooksDir = (git rev-parse --git-path hooks 2>$null | Select-Object -First 1).Trim()
    if (-not $hooksDir) {
        $hooksDir = Join-Path $gitRoot ".git\hooks"
    }
    if (-not (Test-Path $hooksDir)) {
        New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
    }

    $hookPath = Join-Path $hooksDir $HookType
    $runCommand = if ($HookType -eq "commit-msg") { 'gga run \"$1\"' } else { "gga run" }

    $GGA_MARKER_START = "# ======== GGA START ========"
    $GGA_MARKER_END = "# ======== GGA END ========"

    if (Test-Path $hookPath) {
        $content = Get-Content $hookPath -Raw
        if ($content -match [regex]::Escape($GGA_MARKER_START)) {
            Write-Color "Gentleman Guardian Angel hook already installed in $HookType" "Yellow"
            exit 0
        }

        if ($content -match "ai-code-review") {
            Write-Color "Found legacy 'ai-code-review' in hook, migrating to 'gga'..." "Yellow"
            $content = $content -replace "ai-code-review", "gga"
            $content = $content -replace "AI Code Review", "Gentleman Guardian Angel"
            Write-TextFileNoBom -Path $hookPath -Content $content
            Write-Color "Migrated hook to use 'gga'" "Green"
            exit 0
        }

        Write-Color "Existing $HookType hook found, appending GGA..." "Blue"
        $ggaBlock = @"

$GGA_MARKER_START
# Gentleman Guardian Angel - Code Review
if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -ExecutionPolicy Bypass -Command "$runCommand"
  rc=`$?
else
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$runCommand"
  rc=`$?
fi
[ `$rc -eq 0 ] || exit 1
$GGA_MARKER_END
"@
        if ($content -match '(?m)^\s*exit\s*\d*\s*$') {
            $lines = $content -split "`r?`n"
            $lastExitIdx = -1
            for ($i = $lines.Length - 1; $i -ge 0; $i--) {
                if ($lines[$i] -match '^\s*exit\s*\d*\s*$') {
                    $lastExitIdx = $i
                    break
                }
            }
            if ($lastExitIdx -ge 0) {
                $before = if ($lastExitIdx -gt 0) { ($lines[0..($lastExitIdx - 1)] -join "`n") } else { "" }
                $after = $lines[$lastExitIdx..($lines.Length - 1)] -join "`n"
                $content = ($before + "`n" + $ggaBlock + "`n" + $after).TrimStart("`n")
            } else {
                $content += $ggaBlock
            }
        } else {
            $content += $ggaBlock
        }
        Write-TextFileNoBom -Path $hookPath -Content $content
        Write-Color "Appended Gentleman Guardian Angel to existing $HookType hook: $hookPath" "Green"
        exit 0
    }

    $hookScript = @"
#!/bin/sh

$GGA_MARKER_START
# Gentleman Guardian Angel - Code Review
if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -ExecutionPolicy Bypass -Command "$runCommand"
  rc=`$?
else
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$runCommand"
  rc=`$?
fi
[ `$rc -eq 0 ] || exit 1
$GGA_MARKER_END
"@
    Write-TextFileNoBom -Path $hookPath -Content $hookScript

    Write-Color "Installed $HookType hook: $hookPath" "Green"
    Write-Host ""
}

function Uninstall-Hook {
    Write-Banner

    $gitRoot = git rev-parse --show-toplevel 2>$null
    if (-not $gitRoot) {
        Write-Color "Not a git repository" "Red"
        exit 1
    }

    $hooksDir = (git rev-parse --git-path hooks 2>$null | Select-Object -First 1).Trim()
    if (-not $hooksDir) {
        $hooksDir = Join-Path $gitRoot ".git\hooks"
    }
    $foundAny = $false

    foreach ($hookType in @("pre-commit", "commit-msg")) {
        $hookPath = Join-Path $hooksDir $hookType
        if (-not (Test-Path $hookPath)) {
            continue
        }

        $content = Get-Content $hookPath -Raw
        if ($content -match [regex]::Escape("# ======== GGA START ========")) {
            $foundAny = $true
            $content = $content -replace '(?s)# ======== GGA START ========.*?# ======== GGA END ========\r?\n?', ''
            $content = $content -replace '(?s)# Gentleman Guardian Angel.*?(pwsh|powershell\.exe).*?\r?\n?', ''
            $trimmedContent = $content.Trim()
            $contentWithoutShebang = $trimmedContent -replace '(?m)^#!.*\r?\n?', ''

            if ($trimmedContent -match '^\s*#!\s*/' -and $contentWithoutShebang.Trim()) {
                Write-TextFileNoBom -Path $hookPath -Content $trimmedContent
                Write-Color "Removed Gentleman Guardian Angel from $hookType hook" "Green"
            } else {
                Remove-Item $hookPath -Force
                Write-Color "Removed $hookType hook (was GGA-only)" "Green"
            }
        } elseif ($content -match '(?m)^\s*gga\s+run') {
            $foundAny = $true
            $content = $content -replace '(?m)^\s*#\s*Gentleman Guardian Angel.*\r?\n?', ''
            $content = $content -replace '(?m)^\s*gga\s+run.*\r?\n?', ''
            $trimmedContent = $content.Trim()
            $contentWithoutShebang = $trimmedContent -replace '(?m)^#!.*\r?\n?', ''

            if ($trimmedContent -match '^\s*#!\s*/' -and $contentWithoutShebang.Trim()) {
                Write-TextFileNoBom -Path $hookPath -Content $trimmedContent
                Write-Color "Removed Gentleman Guardian Angel from $hookType hook" "Green"
            } else {
                Remove-Item $hookPath -Force
                Write-Color "Removed $hookType hook (was GGA-only)" "Green"
            }
        }
    }

    if (-not $foundAny) {
        Write-Color "Gentleman Guardian Angel hook not found" "Yellow"
    }
    Write-Host ""
}

function Clear-Cache {
    param([string]$SubCommand = "status")

    Write-Banner
    Load-Config
    $configFiles = Get-ConfigFilesForCache

    switch ($SubCommand) {
        "clear" {
            Clear-Project-Cache
            Write-Color "Cleared cache for current project" "Green"
            Write-Host ""
        }
        "clear-all" {
            Clear-All-Cache
            Write-Color "Cleared all cache data" "Green"
            Write-Host ""
        }
        "status" {
            $cacheDir = Get-ProjectCacheDir

            Write-Color -Message "Cache Status:" -Color "White"
            Write-Host ""

            if (-not $cacheDir) {
                Write-Color "  Project cache: Not initialized (not in a git repo?)" "Yellow"
            } elseif (-not (Test-Path $cacheDir)) {
                Write-Color "  Project cache: Not initialized" "Yellow"
            } else {
                Write-Color "  Cache directory: $cacheDir" "Cyan"

                if (Test-Cache-Valid $script:RULES_FILE $configFiles) {
                    Write-Color "  Cache validity: Valid" "Green"
                } else {
                    Write-Color "  Cache validity: Invalid (rules or config changed)" "Yellow"
                }

                $filesDir = Join-Path $cacheDir "files"
                if (Test-Path $filesDir) {
                    $cachedCount = (Get-ChildItem $filesDir -File).Count
                    Write-Color "  Cached files: $cachedCount" "Cyan"
                }

                $cacheSize = (Get-ChildItem $cacheDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
                if ($cacheSize) {
                    $sizeStr = "{0:N2} MB" -f ($cacheSize / 1MB)
                    Write-Color "  Cache size: $sizeStr" "Cyan"
                }
            }
            Write-Host ""
        }
        default {
            Write-Color "Unknown cache command: $SubCommand" "Red"
            Write-Host ""
            Write-Host "Available commands:"
            Write-Host "  gga cache status     - Show cache status"
            Write-Host "  gga cache clear      - Clear project cache"
            Write-Host "  gga cache clear-all  - Clear all cache"
            Write-Host ""
            exit 1
        }
    }
}

function Invoke-Run {
    param(
        [switch]$NoCache,
        [switch]$Ci,
        [switch]$PrMode,
        [switch]$DiffOnly,
        [string]$CommitMsgFile = ""
    )

    if (-not (Validate-PrModeFlags $PrMode $DiffOnly)) {
        exit 1
    }

    Write-Banner
    Load-Config
    $configFiles = Get-ConfigFilesForCache

    if (-not $script:PROVIDER) {
        Write-Color "No provider configured" "Red"
        Write-Host ""
        Write-Host "Configure a provider in .gga or set `$env:GGA_PROVIDER"
        Write-Host "Run 'gga init' to create a config file"
        Write-Host ""
        exit 1
    }

    if (-not (Test-Provider $script:PROVIDER)) {
        exit 1
    }

    if (-not (Test-Path $script:RULES_FILE)) {
        Write-Color "Rules file not found: $($script:RULES_FILE)" "Red"
        Write-Host ""
        Write-Host "Please create a $($script:RULES_FILE) file with your coding standards."
        Write-Host ""
        exit 1
    }

    $useCache = -not $NoCache
    if ($Ci -or $PrMode) { $useCache = $false }

    Write-Color "Provider: $($script:PROVIDER)" "Blue"
    Write-Color "Rules file: $($script:RULES_FILE)" "Blue"
    Write-Color "File patterns: $($script:FILE_PATTERNS)" "Blue"
    if ($script:EXCLUDE_PATTERNS) {
        Write-Color "Exclude patterns: $($script:EXCLUDE_PATTERNS)" "Blue"
    }

    if ($PrMode) {
        if ($DiffOnly) {
            Write-Color "Mode: PR (diff-only review)" "Cyan"
        } else {
            Write-Color "Mode: PR (full file review)" "Cyan"
        }
    } elseif ($Ci) {
        Write-Color "Mode: CI (reviewing last commit)" "Cyan"
    }
    Write-Host ""

    if ($useCache) {
        Write-Color "Cache: enabled" "Green"
    } elseif ($PrMode) {
        Write-Color "Cache: disabled (PR mode)" "Yellow"
    } elseif ($Ci) {
        Write-Color "Cache: disabled (CI mode)" "Yellow"
    } else {
        Write-Color "Cache: disabled (--no-cache)" "Yellow"
    }
    Write-Host ""

    $filesToCheck = ""
    $prRange = ""
    $prBase = ""

    if ($PrMode) {
        $prRange = Get-PrRange $script:PR_BASE_BRANCH
        if (-not $prRange) {
            Write-Color "Could not determine PR range" "Red"
            Write-Host ""
            Write-Host "Set PR_BASE_BRANCH in your .gga config to specify the base branch."
            Write-Host ""
            exit 1
        }
        $prBase = ($prRange -split '\.\.\.')[0]
        Write-Color "PR range: $prRange" "Cyan"
        $filesToCheck = Get-PrFiles $prRange $script:FILE_PATTERNS $script:EXCLUDE_PATTERNS
        if (-not $filesToCheck) {
            Write-Color "No matching files changed in PR" "Yellow"
            Write-Host ""
            exit 0
        }
    } elseif ($Ci) {
        $filesToCheck = Get-CiFiles $script:FILE_PATTERNS $script:EXCLUDE_PATTERNS
        if (-not $filesToCheck) {
            Write-Color "No matching files changed in last commit" "Yellow"
            Write-Host ""
            exit 0
        }
    } else {
        $filesToCheck = Get-StagedFiles $script:FILE_PATTERNS $script:EXCLUDE_PATTERNS
        if (-not $filesToCheck) {
            Write-Color "No matching files staged for commit" "Yellow"
            Write-Host ""
            exit 0
        }
    }

    $filesToReview = $filesToCheck
    $cacheInitialized = $false

    if ($useCache) {
        if (-not (Test-Cache-Valid $script:RULES_FILE $configFiles)) {
            Write-Color "Cache invalidated (rules or config changed)" "Blue"
            Invalidate-Cache
        }

        $cacheDir = Initialize-Cache $script:RULES_FILE $configFiles
        $cacheInitialized = $true

        $filesToReview = Filter-UncachedFiles $filesToCheck
    }

    Write-Color -Message "Files to review:" -Color "White"
    if (-not $filesToReview) {
        Write-Color "  All files passed from cache!" "Green"
        Write-Host ""
        Write-Color "CODE REVIEW PASSED (cached)" "Green"
        Write-Host ""
        exit 0
    }

    $filesToReview | ForEach-Object { Write-Host "  - $_" }
    Write-Host ""

    $rules = Get-Content $script:RULES_FILE -Raw

    $prompt = ""
    $commitMsg = ""
    if ($CommitMsgFile) {
        if (Test-Path -Path $CommitMsgFile -PathType Leaf) {
            $commitMsg = Get-Content -Path $CommitMsgFile -Raw
        } else {
            Write-Color "Commit message file not found: $CommitMsgFile" "Yellow"
        }
    }
    if ($PrMode) {
        $prDiff = if ($DiffOnly) { Get-PrDiff $prRange } else { "" }
        $prompt = Build-PrPrompt $rules $filesToReview $DiffOnly $prDiff $prBase
    } else {
        $useStaged = -not $Ci
        $prompt = Build-Prompt $rules $filesToReview $useStaged $commitMsg
    }

    Write-Color "Sending to $($script:PROVIDER) for review (timeout: $($script:TIMEOUT)s)..." "Blue"
    Write-Host ""

    $providerResult = Execute-ProviderWithTimeout $script:PROVIDER $prompt $script:TIMEOUT
    $result = $providerResult.Output
    $execStatus = $providerResult.ExitCode

    if ($providerResult.TimedOut) {
        Write-Color "Provider timed out after $($script:TIMEOUT)s" "Red"
        Write-Host ""
        Write-Host "The AI provider did not respond in time."
        Write-Host "Try: Increase TIMEOUT in .gga config, or review fewer files."
        Write-Host ""
        if ($script:STRICT_MODE) { exit 1 }
        exit 0
    }

    if ($execStatus -ne 0) {
        Write-Color "Provider execution failed (exit code: $execStatus)" "Red"
        if ($result) {
            Write-Host ""
            Write-Host $result
            Write-Host ""
        }
        if ($script:STRICT_MODE) { exit 1 }
        exit 0
    }

    Write-Host $result
    Write-Host ""

    $statusCheck = ($result -split "`n" | Select-Object -First 15) -join "`n"

    if ($statusCheck -match "STATUS: PASSED") {
        if ($cacheInitialized) {
            Cache-FilesPassed $filesToReview
        }
        Write-Color "CODE REVIEW PASSED" "Green"
        Write-Host ""
        exit 0
    } elseif ($statusCheck -match "STATUS: FAILED") {
        Write-Color "CODE REVIEW FAILED" "Red"
        Write-Host ""
        Write-Host "Fix the violations listed above before committing."
        Write-Host ""
        exit 1
    } else {
        Write-Color "Could not determine review status" "Yellow"
        if ($script:STRICT_MODE) {
            Write-Color "STRICT MODE: Failing due to ambiguous response" "Red"
            Write-Host ""
            Write-Host "Expected 'STATUS: PASSED' or 'STATUS: FAILED' in the first 15 lines"
            Write-Host "Set STRICT_MODE=false in config to allow ambiguous responses"
            Write-Host ""
            exit 1
        } else {
            Write-Color "Allowing commit (STRICT_MODE=false)" "Yellow"
            Write-Host ""
            exit 0
        }
    }
}

switch ($cmd) {
    "run" {
        $noCache = $allArgs -contains "--no-cache"
        $ci = $allArgs -contains "--ci"
        $prMode = $allArgs -contains "--pr-mode"
        $diffOnly = $allArgs -contains "--diff-only"
        $commitMsgFile = ""
        $commitMsgFileIdx = [Array]::IndexOf($allArgs, "--commit-msg-file")
        if ($commitMsgFileIdx -ge 0 -and ($commitMsgFileIdx + 1) -lt $allArgs.Count) {
            $commitMsgFile = $allArgs[$commitMsgFileIdx + 1]
        }
        if (-not $commitMsgFile -and $allArgs.Count -gt 1) {
            foreach ($arg in $allArgs[1..($allArgs.Count - 1)]) {
                if ($arg -notmatch '^--' -and (Test-Path -Path $arg -PathType Leaf)) {
                    $commitMsgFile = $arg
                    break
                }
            }
        }
        Invoke-Run -NoCache:$noCache -Ci:$ci -PrMode:$prMode -DiffOnly:$diffOnly -CommitMsgFile $commitMsgFile
    }
    "install" {
        $hookType = if ($allArgs -contains "--commit-msg") { "commit-msg" } else { "pre-commit" }
        Install-Hook -HookType $hookType
    }
    "uninstall" {
        Uninstall-Hook
    }
    "config" {
        Show-Config
    }
    "init" {
        Initialize-Config
    }
    "cache" {
        $subCmd = if ($allArgs.Count -gt 1) { $allArgs[1] } else { "status" }
        Clear-Cache -SubCommand $subCmd
    }
    "version" { 
        Get-Version 
    }
    "v" { 
        Get-Version 
    }
    "--version" { 
        Get-Version 
    }
    "help" { 
        Get-Help 
    }
    "h" { 
        Get-Help 
    }
    "--help" { 
        Get-Help 
    }
    "" { 
        Get-Help 
    }
    default {
        Write-Color "Unknown command: $cmd" "Red"
        Write-Host ""
        Get-Help
        exit 1
    }
}
