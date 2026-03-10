# ============================================================================
# Gentleman Guardian Angel - PR Mode Functions (PowerShell)
# ============================================================================

function Detect-BaseBranch {
    $branches = git for-each-ref --format='%(refname:short)' refs/heads 2>$null
    if (-not $branches) {
        Write-Error "Could not detect base branch (not a git repo?)"
        return ""
    }

    foreach ($candidate in @("main", "master", "develop", "dev")) {
        if (($branches -split "`n" | ForEach-Object { $_.Trim() }) -contains $candidate) {
            return $candidate
        }
    }

    Write-Error "Could not detect base branch. No main, master, develop, or dev branch found. Set PR_BASE_BRANCH in your .gga config."
    return ""
}

function Get-PrRange {
    param([string]$PrBaseBranch = "")

    if ($PrBaseBranch) {
        return "${PrBaseBranch}...HEAD"
    }

    $base = Detect-BaseBranch
    if (-not $base) {
        return ""
    }

    return "${base}...HEAD"
}

function Get-PrFiles {
    param([string]$Range, [string]$Patterns, [string]$Excludes)

    $changed = git diff --name-only --diff-filter=ACM $Range 2>$null
    if (-not $changed) {
        return ""
    }

    $patternArray = $Patterns -split ','
    $excludeArray = if ($Excludes) { $Excludes -split ',' } else { @() }

    $result = @()
    $changed -split "`n" | ForEach-Object {
        $file = $_.Trim()
        if (-not $file) { return }

        $match = $false
        $excluded = $false

        foreach ($pattern in $patternArray) {
            $pattern = $pattern.Trim()
            if ($pattern -eq "*") {
                $match = $true
                break
            } elseif ($pattern.StartsWith("*")) {
                $suffix = $pattern.Substring(1)
                if ($file.EndsWith($suffix)) {
                    $match = $true
                    break
                }
            } else {
                if ($file -eq $pattern -or (Split-Path $file -Leaf) -eq $pattern) {
                    $match = $true
                    break
                }
            }
        }

        if ($match -and $Excludes) {
            foreach ($pattern in $excludeArray) {
                $pattern = $pattern.Trim()
                if ($pattern.StartsWith("*")) {
                    $suffix = $pattern.Substring(1)
                    if ($file.EndsWith($suffix)) {
                        $excluded = $true
                        break
                    }
                } else {
                    if ($file -eq $pattern -or (Split-Path $file -Leaf) -eq $pattern) {
                        $excluded = $true
                        break
                    }
                }
            }
        }

        if ($match -and -not $excluded -and (Test-Path $file)) {
            $result += $file
        }
    }

    return $result -join "`n"
}

function Get-PrDiff {
    param([string]$Range)
    git diff $Range 2>$null
}

function Validate-PrModeFlags {
    param([bool]$PrMode, [bool]$DiffOnly)

    if ($DiffOnly -and -not $PrMode) {
        Write-Color "--diff-only can only be used with --pr-mode" "Red"
        return $false
    }
    return $true
}

function Build-PrPrompt {
    param(
        [string]$Rules,
        [string]$Files,
        [bool]$DiffOnly,
        [string]$DiffContent,
        [string]$BaseBranch
    )

    $sb = [System.Text.StringBuilder]::new()

    [void]$sb.AppendLine("You are a code reviewer analyzing a pull request against the $BaseBranch branch.")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("=== CODING STANDARDS ===")
    [void]$sb.AppendLine($Rules)
    [void]$sb.AppendLine("=== END CODING STANDARDS ===")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("=== PR CONTEXT ===")
    [void]$sb.AppendLine("This is a pull request review. The following files were changed in this PR (compared to $BaseBranch).")
    [void]$sb.AppendLine("=== END PR CONTEXT ===")

    if ($DiffOnly -and $DiffContent) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("=== PR DIFF ===")
        [void]$sb.AppendLine($DiffContent)
        [void]$sb.AppendLine("=== END PR DIFF ===")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("=== FILES (complete content for context) ===")
    } else {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("=== FILES TO REVIEW ===")
    }

    $Files -split "`n" | ForEach-Object {
        $file = $_.Trim()
        if ($file) {
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("--- FILE: $file ---")
            if (Test-Path $file) {
                [void]$sb.AppendLine((Get-Content $file -Raw))
            }
        }
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("=== END FILES ===")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**IMPORTANT: Your response MUST include one of these lines near the beginning:**")
    [void]$sb.AppendLine("STATUS: PASSED")
    [void]$sb.AppendLine("STATUS: FAILED")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**If FAILED:** List each violation with:")
    [void]$sb.AppendLine("- File name")
    [void]$sb.AppendLine("- Line number (if applicable)")
    [void]$sb.AppendLine("- Rule violated")
    [void]$sb.AppendLine("- Description of the issue")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**If PASSED:** Confirm all files comply with the coding standards.")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**Begin with STATUS:**")

    return $sb.ToString()
}

function Build-Prompt {
    param(
        [string]$Rules,
        [string]$Files,
        [bool]$UseStaged = $true,
        [string]$CommitMsg = ""
    )

    $sb = [System.Text.StringBuilder]::new()

    [void]$sb.AppendLine("You are a code reviewer. Analyze the files below and validate they comply with the coding standards provided.")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("=== CODING STANDARDS ===")
    [void]$sb.AppendLine($Rules)
    [void]$sb.AppendLine("=== END CODING STANDARDS ===")

    if ($CommitMsg) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("=== COMMIT MESSAGE ===")
        [void]$sb.AppendLine($CommitMsg)
        [void]$sb.AppendLine("=== END COMMIT MESSAGE ===")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("=== FILES TO REVIEW ===")

    $Files -split "`n" | ForEach-Object {
        $file = $_.Trim()
        if ($file) {
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("--- FILE: $file ---")
            if ($UseStaged) {
                $stagedContent = git show ":$file" 2>$null
                if ($stagedContent) {
                    [void]$sb.AppendLine($stagedContent)
                } else {
                    Write-Color "Could not read staged content for: $file" "Yellow"
                }
            } else {
                if (Test-Path $file) {
                    [void]$sb.AppendLine((Get-Content $file -Raw))
                }
            }
        }
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("=== END FILES ===")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**IMPORTANT: Your response MUST include one of these lines near the beginning:**")
    [void]$sb.AppendLine("STATUS: PASSED")
    [void]$sb.AppendLine("STATUS: FAILED")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**If FAILED:** List each violation with:")
    [void]$sb.AppendLine("- File name")
    [void]$sb.AppendLine("- Line number (if applicable)")
    [void]$sb.AppendLine("- Rule violated")
    [void]$sb.AppendLine("- Description of the issue")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**If PASSED:** Confirm all files comply with the coding standards.")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**Begin with STATUS:**")

    return $sb.ToString()
}

function Get-StagedFiles {
    param([string]$Patterns, [string]$Excludes)

    $staged = git diff --cached --name-only --diff-filter=ACM 2>$null
    if (-not $staged) {
        return ""
    }

    $patternArray = $Patterns -split ','
    $excludeArray = if ($Excludes) { $Excludes -split ',' } else { @() }

    $result = @()
    $staged -split "`n" | ForEach-Object {
        $file = $_.Trim()
        if (-not $file) { return }

        $match = $false
        $excluded = $false

        foreach ($pattern in $patternArray) {
            $pattern = $pattern.Trim()
            if ($pattern -eq "*") {
                $match = $true
                break
            } elseif ($pattern.StartsWith("*")) {
                $suffix = $pattern.Substring(1)
                if ($file.EndsWith($suffix)) {
                    $match = $true
                    break
                }
            } else {
                if ($file -eq $pattern -or (Split-Path $file -Leaf) -eq $pattern) {
                    $match = $true
                    break
                }
            }
        }

        if ($match -and $Excludes) {
            foreach ($pattern in $excludeArray) {
                $pattern = $pattern.Trim()
                if ($pattern.StartsWith("*")) {
                    $suffix = $pattern.Substring(1)
                    if ($file.EndsWith($suffix)) {
                        $excluded = $true
                        break
                    }
                } else {
                    if ($file -eq $pattern -or (Split-Path $file -Leaf) -eq $pattern) {
                        $excluded = $true
                        break
                    }
                }
            }
        }

        if ($match -and -not $excluded) {
            $result += $file
        }
    }

    return $result -join "`n"
}

function Get-CiFiles {
    param([string]$Patterns, [string]$Excludes)

    $sourceCommit = if ($env:GGA_CI_SOURCE_COMMIT) { $env:GGA_CI_SOURCE_COMMIT } else { "HEAD~1" }

    $changed = git diff --name-only --diff-filter=ACM "$sourceCommit..HEAD" 2>$null
    if (-not $changed) {
        return ""
    }

    $patternArray = $Patterns -split ','
    $excludeArray = if ($Excludes) { $Excludes -split ',' } else { @() }

    $result = @()
    $changed -split "`n" | ForEach-Object {
        $file = $_.Trim()
        if (-not $file) { return }

        $match = $false
        $excluded = $false

        foreach ($pattern in $patternArray) {
            $pattern = $pattern.Trim()
            if ($pattern -eq "*") {
                $match = $true
                break
            } elseif ($pattern.StartsWith("*")) {
                $suffix = $pattern.Substring(1)
                if ($file.EndsWith($suffix)) {
                    $match = $true
                    break
                }
            } else {
                if ($file -eq $pattern -or (Split-Path $file -Leaf) -eq $pattern) {
                    $match = $true
                    break
                }
            }
        }

        if ($match -and $Excludes) {
            foreach ($pattern in $excludeArray) {
                $pattern = $pattern.Trim()
                if ($pattern.StartsWith("*")) {
                    $suffix = $pattern.Substring(1)
                    if ($file.EndsWith($suffix)) {
                        $excluded = $true
                        break
                    }
                } else {
                    if ($file -eq $pattern -or (Split-Path $file -Leaf) -eq $pattern) {
                        $excluded = $true
                        break
                    }
                }
            }
        }

        if ($match -and -not $excluded -and (Test-Path $file)) {
            $result += $file
        }
    }

    return $result -join "`n"
}
