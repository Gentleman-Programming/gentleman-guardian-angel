# shellcheck shell=bash

Describe 'format_review_output()'
  # Define colors used by the function
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  NC='\033[0m'

  # Copy the format_review_output function for testing
  format_review_output() {
    local result="$1"

    # If stdout is not a terminal, output plain text without formatting
    if [[ ! -t 1 ]]; then
      echo "$result"
      return
    fi

    # Print separator before output
    echo -e "${CYAN}─────────${NC} ${BOLD}Review Result${NC} ${CYAN}─────────${NC}"
    echo ""

    # Process each line and apply formatting
    while IFS= read -r line || [[ -n "$line" ]]; do
      # Colorize STATUS: PASSED (handle markdown bold syntax too)
      if [[ "$line" =~ ^\*?\*?STATUS:[[:space:]]*PASSED\*?\*?$ ]] || [[ "$line" =~ ^STATUS:[[:space:]]*PASSED ]]; then
        echo -e "${GREEN}${BOLD}${line}${NC}"
      # Colorize STATUS: FAILED (handle markdown bold syntax too)
      elif [[ "$line" =~ ^\*?\*?STATUS:[[:space:]]*FAILED\*?\*?$ ]] || [[ "$line" =~ ^STATUS:[[:space:]]*FAILED ]]; then
        echo -e "${RED}${BOLD}${line}${NC}"
      # Colorize numbered findings (#N file:line - ...)
      elif [[ "$line" =~ ^#([0-9]+)[[:space:]]([^[:space:]]+)(.*) ]]; then
        local num="${BASH_REMATCH[1]}"
        local file="${BASH_REMATCH[2]}"
        local rest="${BASH_REMATCH[3]}"
        echo -e "${YELLOW}#${num}${NC} ${CYAN}${file}${NC}${rest}"
      else
        echo "$line"
      fi
    done <<< "$result"

    echo ""
    echo -e "${CYAN}──────────────────────────────────${NC}"
  }

  # Test variant that forces formatting (for testing color output)
  format_review_output_with_colors() {
    local result="$1"

    # Print separator before output
    echo -e "${CYAN}─────────${NC} ${BOLD}Review Result${NC} ${CYAN}─────────${NC}"
    echo ""

    # Process each line and apply formatting
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^\*?\*?STATUS:[[:space:]]*PASSED\*?\*?$ ]] || [[ "$line" =~ ^STATUS:[[:space:]]*PASSED ]]; then
        echo -e "${GREEN}${BOLD}${line}${NC}"
      elif [[ "$line" =~ ^\*?\*?STATUS:[[:space:]]*FAILED\*?\*?$ ]] || [[ "$line" =~ ^STATUS:[[:space:]]*FAILED ]]; then
        echo -e "${RED}${BOLD}${line}${NC}"
      elif [[ "$line" =~ ^#([0-9]+)[[:space:]]([^[:space:]]+)(.*) ]]; then
        local num="${BASH_REMATCH[1]}"
        local file="${BASH_REMATCH[2]}"
        local rest="${BASH_REMATCH[3]}"
        echo -e "${YELLOW}#${num}${NC} ${CYAN}${file}${NC}${rest}"
      else
        echo "$line"
      fi
    done <<< "$result"

    echo ""
    echo -e "${CYAN}──────────────────────────────────${NC}"
  }

  Describe 'plain text output (non-terminal)'
    It 'outputs plain text when stdout is not a terminal'
      result="STATUS: PASSED
All files comply with coding standards."

      When call format_review_output "$result"
      The output should equal "$result"
    End

    It 'preserves multiline output without modification'
      result="STATUS: FAILED
#1 src/file.ts:10 - naming - Invalid name
#2 src/file.ts:20 - style - Missing semicolon"

      When call format_review_output "$result"
      The output should equal "$result"
    End
  End

  Describe 'formatted output (terminal mode)'
    It 'includes header separator'
      result="STATUS: PASSED"

      When call format_review_output_with_colors "$result"
      The output should include "Review Result"
    End

    It 'colorizes STATUS: PASSED in green'
      result="STATUS: PASSED"

      When call format_review_output_with_colors "$result"
      # Check that green color code is present
      The output should include $'\033[0;32m'
    End

    It 'colorizes STATUS: FAILED in red'
      result="STATUS: FAILED"

      When call format_review_output_with_colors "$result"
      # Check that red color code is present
      The output should include $'\033[0;31m'
    End

    It 'colorizes numbered findings with yellow number'
      result="#1 src/file.ts:10 - naming - Invalid name"

      When call format_review_output_with_colors "$result"
      # Check that yellow color code is present for the number
      The output should include $'\033[1;33m'
    End

    It 'colorizes file reference in cyan'
      result="#1 src/file.ts:10 - naming - Invalid name"

      When call format_review_output_with_colors "$result"
      # Check that cyan color code is present for the file
      The output should include $'\033[0;36m'
    End

    It 'handles markdown bold STATUS syntax'
      result="**STATUS: PASSED**"

      When call format_review_output_with_colors "$result"
      # Should still apply green coloring
      The output should include $'\033[0;32m'
    End

    It 'preserves non-matching lines without color codes'
      result="This is a regular line"

      When call format_review_output_with_colors "$result"
      The output should include "This is a regular line"
    End

    It 'handles multiple findings correctly'
      result="STATUS: FAILED
#1 src/a.ts:5 - error - First issue
#2 src/b.ts:10 - warning - Second issue
#3 lib/c.ts:15 - info - Third issue"

      When call format_review_output_with_colors "$result"
      The output should include "#1"
      The output should include "#2"
      The output should include "#3"
      The output should include "src/a.ts:5"
      The output should include "src/b.ts:10"
      The output should include "lib/c.ts:15"
    End
  End

  Describe 'edge cases'
    It 'handles empty result'
      result=""

      When call format_review_output "$result"
      The output should equal ""
      The status should be success
    End

    It 'handles findings with special characters in description'
      result="#1 src/file.ts:10 - rule - Description with \"quotes\" and 'apostrophes'"

      When call format_review_output "$result"
      The output should include "quotes"
      The output should include "apostrophes"
    End

    It 'handles STATUS with extra whitespace'
      result="STATUS:   PASSED"

      When call format_review_output_with_colors "$result"
      The output should include $'\033[0;32m'
    End
  End
End