# shellcheck shell=bash

Describe 'STATUS parsing (Issue #18)'
  # Test the status parsing logic directly
  # The parsing should find exactly one STATUS verdict in the first 30 lines,
  # accept markdown formatting like **STATUS: PASSED**, and treat
  # conflicting verdicts as ambiguous.

  parse_status() {
    local response="$1"
    local max_lines="${2:-30}"
    local line_no=0
    local found_status=""
    local line

    while IFS= read -r line; do
      line_no=$((line_no + 1))
      if [[ "$line_no" -gt "$max_lines" ]]; then
        break
      fi

      line=$(printf '%s' "$line" | sed $'s/\x1b\[[0-9;]*[mK]//g')
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      line="${line#\*\*}"
      line="${line%\*\*}"
      line="${line#\*}"
      line="${line%\*}"
      line="${line#\`}"
      line="${line%\`}"
      line="${line#\# }"
      line="${line#> }"

      if [[ "$line" =~ ^STATUS:[[:space:]]*(PASSED|FAILED)([^[:alnum:]_].*)?$ ]]; then
        local candidate="${BASH_REMATCH[1]}"
        if [[ -z "$found_status" ]]; then
          found_status="$candidate"
        elif [[ "$found_status" != "$candidate" ]]; then
          echo "AMBIGUOUS"
          return 1
        fi
      fi
    done <<< "$response"

    if [[ -n "$found_status" ]]; then
      echo "$found_status"
      return 0
    fi

    echo "AMBIGUOUS"
    return 1
  }

  Describe 'STATUS on first line'
    It 'detects PASSED on first line'
      When call parse_status "STATUS: PASSED
All files comply with standards."
      The output should equal "PASSED"
      The status should be success
    End

    It 'detects FAILED on first line'
      When call parse_status "STATUS: FAILED
- file.ts: missing type annotation"
      The output should equal "FAILED"
      The status should be success
    End
  End

  Describe 'STATUS with preamble text (Issue #18 scenario)'
    It 'detects PASSED after instruction acknowledgment'
      When call parse_status "# 📋 Instructions loaded!
- /path/to/AGENTS.md
- /path/to/config/AGENTS.md
---
STATUS: PASSED
All files comply with standards."
      The output should equal "PASSED"
      The status should be success
    End

    It 'detects FAILED after instruction acknowledgment'
      When call parse_status "# 📋 Instructions loaded!
- /path/to/AGENTS.md
---
STATUS: FAILED
- file.ts: violation found"
      The output should equal "FAILED"
      The status should be success
    End
  End

  Describe 'STATUS with markdown formatting'
    It 'detects **STATUS: PASSED** (bold markdown)'
      When call parse_status "# Review
**STATUS: PASSED**
All good!"
      The output should equal "PASSED"
      The status should be success
    End

    It 'detects **STATUS: FAILED** (bold markdown)'
      When call parse_status "# Review
**STATUS: FAILED**
Issues found."
      The output should equal "FAILED"
      The status should be success
    End

    It 'detects *STATUS: PASSED* (italic markdown)'
      When call parse_status "*STATUS: PASSED*
Review complete."
      The output should equal "PASSED"
      The status should be success
    End

    It 'detects STATUS: PASSED with trailing markdown'
      When call parse_status "STATUS: PASSED ✅
All checks passed."
      The output should equal "PASSED"
      The status should be success
    End
  End

  Describe 'STATUS beyond first 30 lines'
    It 'returns AMBIGUOUS when STATUS is on line 31'
      # 30 lines of preamble + STATUS on line 31 (should not be found)
      response="Line 1
Line 2
Line 3
Line 4
Line 5
Line 6
Line 7
Line 8
Line 9
Line 10
Line 11
Line 12
Line 13
Line 14
Line 15
Line 16
Line 17
Line 18
Line 19
Line 20
Line 21
Line 22
Line 23
Line 24
Line 25
Line 26
Line 27
Line 28
Line 29
Line 30
STATUS: PASSED"
      
      When call parse_status "$response"
      The output should equal "AMBIGUOUS"
      The status should be failure
    End

    It 'detects STATUS on line 30 (boundary)'
      # 29 lines of preamble + STATUS on line 30 (should be found)
      response="Line 1
Line 2
Line 3
Line 4
Line 5
Line 6
Line 7
Line 8
Line 9
Line 10
Line 11
Line 12
Line 13
Line 14
Line 15
Line 16
Line 17
Line 18
Line 19
Line 20
Line 21
Line 22
Line 23
Line 24
Line 25
Line 26
Line 27
Line 28
Line 29
STATUS: PASSED"
      
      When call parse_status "$response"
      The output should equal "PASSED"
      The status should be success
    End
  End

  Describe 'edge cases'
    It 'returns AMBIGUOUS when no STATUS found'
      When call parse_status "This is a review without status.
The code looks good.
No issues found."
      The output should equal "AMBIGUOUS"
      The status should be failure
    End

    It 'returns AMBIGUOUS for empty response'
      When call parse_status ""
      The output should equal "AMBIGUOUS"
      The status should be failure
    End

    It 'returns AMBIGUOUS when STATUS is in middle of line'
      When call parse_status "Review result: STATUS: PASSED - all good"
      The output should equal "AMBIGUOUS"
      The status should be failure
    End

    It 'returns AMBIGUOUS when both PASSED and FAILED are present'
      When call parse_status "STATUS: PASSED
STATUS: FAILED"
      The output should equal "AMBIGUOUS"
      The status should be failure
    End

    It 'strips ANSI sequences before STATUS parsing'
      response=$'\033[0;32mSTATUS: PASSED\033[0m\nAll good'
      When call parse_status "$response"
      The output should equal "PASSED"
      The status should be success
    End
  End
End
