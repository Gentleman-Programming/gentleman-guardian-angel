# shellcheck shell=bash

Describe 'GGA Ignore Feature'

  # Colors (needed by functions)
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  NC='\033[0m'

  # Minimal log helpers
  log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
  log_success() { echo -e "${GREEN}✅ $1${NC}"; }
  log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
  log_error() { echo -e "${RED}❌ $1${NC}"; }

  DEFAULT_GGA_IGNORE_FILE=".gga-ignore"

  # ================================================================
  # Copy functions under test from bin/gga
  # ================================================================

  load_gga_ignore() {
    local ignore_file="${1:-$DEFAULT_GGA_IGNORE_FILE}"
    if [[ ! -f "$ignore_file" ]]; then
      return
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
      line=$(echo "$line" | sed 's/^[[:space:]]*//')
      if [[ -z "$line" || "$line" == \#* ]]; then
        continue
      fi
      echo "$line"
    done < "$ignore_file"
  }

  is_finding_ignored() {
    local file_line="$1"
    local ignore_entries="$2"
    if [[ -z "$ignore_entries" ]]; then
      return 1
    fi
    while IFS= read -r entry; do
      local entry_file_line
      entry_file_line=$(echo "$entry" | sed 's/[[:space:]]*#.*$//' | sed 's/[[:space:]]*$//')
      if [[ "$entry_file_line" == "$file_line" ]]; then
        return 0
      fi
    done <<< "$ignore_entries"
    return 1
  }

  parse_findings() {
    local ai_output="$1"
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^#([0-9]+)[[:space:]]([^[:space:]]+)(.*) ]]; then
        local num="${BASH_REMATCH[1]}"
        local file_ref="${BASH_REMATCH[2]}"
        echo "${num}|${file_ref}|${line}"
      fi
    done <<< "$ai_output"
  }

  add_to_gga_ignore() {
    local file_line="$1"
    local reason="$2"
    local ignore_file="${3:-$DEFAULT_GGA_IGNORE_FILE}"
    if [[ ! -f "$ignore_file" ]]; then
      echo "# .gga-ignore - Dismissed review findings" > "$ignore_file"
      echo "# Format: file:line  # reason" >> "$ignore_file"
      echo "" >> "$ignore_file"
    fi
    echo "${file_line}  # ${reason}" >> "$ignore_file"
  }

  # ================================================================
  # Tests
  # ================================================================

  Describe 'load_gga_ignore()'
    setup() { TEMP_DIR=$(mktemp -d); cd "$TEMP_DIR" || exit 1; }
    cleanup() { rm -rf "$TEMP_DIR"; }
    Before 'setup'
    After 'cleanup'

    It 'returns nothing when file does not exist'
      When call load_gga_ignore
      The output should equal ""
      The status should be success
    End

    It 'parses entries and skips comments and blank lines'
      cat > .gga-ignore << 'IGNORE'
# .gga-ignore - Dismissed review findings
# Format: file:line  # reason

src/file.sql:42  # mart-to-mart es válido
lib/utils.ts:15  # intentional console.log

# Another comment
IGNORE
      When call load_gga_ignore
      The line 1 of output should equal "src/file.sql:42  # mart-to-mart es válido"
      The line 2 of output should equal "lib/utils.ts:15  # intentional console.log"
      The lines of output should equal 2
    End

    It 'handles file with only comments'
      cat > .gga-ignore << 'IGNORE'
# Just comments
# Nothing here
IGNORE
      When call load_gga_ignore
      The output should equal ""
    End

    It 'accepts custom file path'
      echo "src/a.ts:10  # reason" > custom-ignore
      When call load_gga_ignore "custom-ignore"
      The output should include "src/a.ts:10"
    End
  End

  Describe 'is_finding_ignored()'
    It 'returns 0 (success) when file:line is ignored'
      entries="src/file.sql:42  # reason
lib/utils.ts:15  # another reason"
      When call is_finding_ignored "src/file.sql:42" "$entries"
      The status should be success
    End

    It 'returns 1 (failure) when file:line is NOT ignored'
      entries="src/file.sql:42  # reason"
      When call is_finding_ignored "src/other.ts:10" "$entries"
      The status should be failure
    End

    It 'returns 1 when ignore entries are empty'
      When call is_finding_ignored "src/file.sql:42" ""
      The status should be failure
    End

    It 'matches exact file:line only'
      entries="src/file.sql:42  # reason"
      When call is_finding_ignored "src/file.sql:4" "$entries"
      The status should be failure
    End
  End

  Describe 'parse_findings()'
    It 'extracts numbered findings from AI output'
      ai_output="STATUS: FAILED
#1 src/file.ts:10 - naming - Invalid name
#2 src/file.ts:20 - style - Missing semicolon"

      When call parse_findings "$ai_output"
      The line 1 of output should equal "1|src/file.ts:10|#1 src/file.ts:10 - naming - Invalid name"
      The line 2 of output should equal "2|src/file.ts:20|#2 src/file.ts:20 - style - Missing semicolon"
      The lines of output should equal 2
    End

    It 'ignores non-finding lines'
      ai_output="STATUS: FAILED
Some explanation text
#1 src/a.ts:5 - error - issue
More text here"

      When call parse_findings "$ai_output"
      The lines of output should equal 1
      The output should include "1|src/a.ts:5"
    End

    It 'returns empty for PASSED review'
      ai_output="STATUS: PASSED
All files comply with coding standards."

      When call parse_findings "$ai_output"
      The output should equal ""
    End

    It 'handles findings with complex file paths'
      ai_output="#1 src/components/Button.tsx:42 - react - Missing key prop"

      When call parse_findings "$ai_output"
      The output should include "1|src/components/Button.tsx:42"
    End
  End

  Describe 'add_to_gga_ignore()'
    setup() { TEMP_DIR=$(mktemp -d); cd "$TEMP_DIR" || exit 1; }
    cleanup() { rm -rf "$TEMP_DIR"; }
    Before 'setup'
    After 'cleanup'

    It 'creates file with header when it does not exist'
      When call add_to_gga_ignore "src/file.ts:10" "valid pattern"
      The file ".gga-ignore" should be exist
      The contents of file ".gga-ignore" should include "# .gga-ignore"
      The contents of file ".gga-ignore" should include "src/file.ts:10  # valid pattern"
    End

    It 'appends to existing file'
      echo "# existing header" > .gga-ignore
      When call add_to_gga_ignore "src/b.ts:20" "another reason"
      The contents of file ".gga-ignore" should include "# existing header"
      The contents of file ".gga-ignore" should include "src/b.ts:20  # another reason"
    End
  End

  Describe 'cmd_ignore()'
    # Copy cmd_ignore for testing
    print_banner() { :; }  # no-op for tests

    cmd_ignore() {
      local subcommand="${1:-list}"
      case "$subcommand" in
        list)
          print_banner
          local entries
          entries=$(load_gga_ignore)
          if [[ -z "$entries" ]]; then
            log_info "No entries in .gga-ignore"
            if [[ ! -f "$DEFAULT_GGA_IGNORE_FILE" ]]; then
              echo "  File does not exist yet."
            else
              echo "  File exists but has no active entries."
            fi
          else
            echo -e "${BOLD}Ignored findings:${NC}"
            echo ""
            while IFS= read -r entry; do
              echo "  $entry"
            done <<< "$entries"
          fi
          echo ""
          ;;
        clear)
          print_banner
          if [[ -f "$DEFAULT_GGA_IGNORE_FILE" ]]; then
            rm "$DEFAULT_GGA_IGNORE_FILE"
            log_success "Removed .gga-ignore"
          else
            log_info "No .gga-ignore file to remove"
          fi
          echo ""
          ;;
      esac
    }

    setup() { TEMP_DIR=$(mktemp -d); cd "$TEMP_DIR" || exit 1; }
    cleanup() { rm -rf "$TEMP_DIR"; }
    Before 'setup'
    After 'cleanup'

    It 'lists entries from .gga-ignore'
      cat > .gga-ignore << 'IGNORE'
# header
src/a.ts:10  # reason one
IGNORE
      When call cmd_ignore "list"
      The output should include "src/a.ts:10"
      The output should include "reason one"
    End

    It 'shows info when no file exists'
      When call cmd_ignore "list"
      The output should include "No entries"
      The output should include "does not exist"
    End

    It 'shows info for file with only comments'
      echo "# only comments" > .gga-ignore
      When call cmd_ignore "list"
      The output should include "No entries"
      The output should include "no active entries"
    End

    It 'removes .gga-ignore on clear'
      echo "src/a.ts:10  # reason" > .gga-ignore
      When call cmd_ignore "clear"
      The output should include "Removed .gga-ignore"
      The file ".gga-ignore" should not be exist
    End

    It 'handles clear when no file exists'
      When call cmd_ignore "clear"
      The output should include "No .gga-ignore file"
    End
  End

  Describe 'prompt injection into build_prompt()'
    # Simplified build_prompt that only tests the exception injection
    build_prompt_exceptions() {
      local ignore_entries
      ignore_entries=$(load_gga_ignore)

      if [[ -n "$ignore_entries" ]]; then
        echo "=== EXCEPTIONS (do not flag these) ==="
        while IFS= read -r entry; do
          local entry_file_line entry_reason
          entry_file_line=$(echo "$entry" | sed 's/[[:space:]]*#.*$//' | sed 's/[[:space:]]*$//')
          entry_reason=$(echo "$entry" | grep -o '#.*$' | sed 's/^#[[:space:]]*//' || true)
          if [[ -n "$entry_reason" ]]; then
            echo "- ${entry_file_line} (reason: ${entry_reason})"
          else
            echo "- ${entry_file_line}"
          fi
        done <<< "$ignore_entries"
        echo "=== END EXCEPTIONS ==="
      fi
    }

    setup() { TEMP_DIR=$(mktemp -d); cd "$TEMP_DIR" || exit 1; }
    cleanup() { rm -rf "$TEMP_DIR"; }
    Before 'setup'
    After 'cleanup'

    It 'outputs nothing when no .gga-ignore exists'
      When call build_prompt_exceptions
      The output should equal ""
    End

    It 'injects exceptions block when .gga-ignore has entries'
      cat > .gga-ignore << 'IGNORE'
# header
src/file.sql:42  # mart-to-mart es válido
IGNORE
      When call build_prompt_exceptions
      The output should include "=== EXCEPTIONS (do not flag these) ==="
      The output should include "src/file.sql:42 (reason: mart-to-mart es válido)"
      The output should include "=== END EXCEPTIONS ==="
    End

    It 'formats multiple entries correctly'
      cat > .gga-ignore << 'IGNORE'
src/a.ts:10  # reason one
src/b.ts:20  # reason two
IGNORE
      When call build_prompt_exceptions
      The output should include "- src/a.ts:10 (reason: reason one)"
      The output should include "- src/b.ts:20 (reason: reason two)"
    End
  End
End
