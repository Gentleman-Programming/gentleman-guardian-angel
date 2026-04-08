# shellcheck shell=bash

Describe 'STATUS parsing (Issue #18)'
  # Test the status parsing logic directly
  # The parsing should find STATUS: PASSED/FAILED anywhere in the output
  # and accept markdown formatting like **STATUS: PASSED**

  parse_status() {
    local response="$1"
    local status_check
    status_check=$(echo "$response" | grep "STATUS:")

    if echo "$status_check" | grep -q "STATUS: PASSED"; then
      echo "PASSED"
      return 0
    elif echo "$status_check" | grep -q "STATUS: FAILED"; then
      echo "FAILED"
      return 0
    else
      echo "AMBIGUOUS"
      return 1
    fi
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

  Describe 'STATUS beyond first 15 lines (Codex CLI preamble scenario)'
    It 'detects STATUS on line 16 (searches entire output)'
      # Codex CLI outputs ~15 lines of session metadata before the AI response
      # The parser must search the entire output, not just the first N lines
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
STATUS: PASSED"

      When call parse_status "$response"
      The output should equal "PASSED"
      The status should be success
    End

    It 'detects STATUS on line 30 (deep in output)'
      # Some providers output extensive metadata before the actual review
      response="$(printf 'Preamble line\n%.0s' {1..29})
STATUS: FAILED"

      When call parse_status "$response"
      The output should equal "FAILED"
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

    It 'handles STATUS in middle of line'
      When call parse_status "Review result: STATUS: PASSED - all good"
      The output should equal "PASSED"
      The status should be success
    End

    It 'prioritizes first STATUS found (PASSED before FAILED)'
      When call parse_status "STATUS: PASSED
Note: Almost STATUS: FAILED on one check"
      The output should equal "PASSED"
      The status should be success
    End
  End
End
