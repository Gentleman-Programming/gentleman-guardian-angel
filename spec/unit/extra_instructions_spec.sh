# shellcheck shell=bash

Describe 'EXTRA_INSTRUCTIONS feature'
  # We need to source the main script to get build_prompt
  # But we'll test via config loading which is safer

  Describe 'Multiline EXTRA_INSTRUCTIONS parsing'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR" || exit 1
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'parses heredoc-style multiline instructions'
      cat > .gga << 'EOF'
PROVIDER="claude"
EXTRA_INSTRUCTIONS=$(cat <<'INSTRUCTIONS'
Line one of instructions.
Line two of instructions.
Line three of instructions.
INSTRUCTIONS
)
EOF
      # shellcheck source=/dev/null
      source .gga
      The variable PROVIDER should eq "claude"
      The variable EXTRA_INSTRUCTIONS should include "Line one"
      The variable EXTRA_INSTRUCTIONS should include "Line two"
      The variable EXTRA_INSTRUCTIONS should include "Line three"
    End

    It 'parses ANSI-C quoting style with newlines'
      cat > .gga << 'EOF'
PROVIDER="claude"
EXTRA_INSTRUCTIONS=$'First line.\nSecond line.\nThird line.'
EOF
      # shellcheck source=/dev/null
      source .gga
      The variable PROVIDER should eq "claude"
      The variable EXTRA_INSTRUCTIONS should include "First line"
      The variable EXTRA_INSTRUCTIONS should include "Second line"
      The variable EXTRA_INSTRUCTIONS should include "Third line"
    End

    It 'parses simple single-line instructions'
      cat > .gga << 'EOF'
PROVIDER="claude"
EXTRA_INSTRUCTIONS="Focus on security and error handling."
EOF
      # shellcheck source=/dev/null
      source .gga
      The variable PROVIDER should eq "claude"
      The variable EXTRA_INSTRUCTIONS should eq "Focus on security and error handling."
    End

    It 'handles empty EXTRA_INSTRUCTIONS'
      cat > .gga << 'EOF'
PROVIDER="claude"
EXTRA_INSTRUCTIONS=""
EOF
      # shellcheck source=/dev/null
      source .gga
      The variable EXTRA_INSTRUCTIONS should eq ""
    End

    It 'handles missing EXTRA_INSTRUCTIONS (undefined)'
      cat > .gga << 'EOF'
PROVIDER="claude"
EOF
      # shellcheck source=/dev/null
      source .gga
      The variable PROVIDER should eq "claude"
      # EXTRA_INSTRUCTIONS should be unset or empty
      The variable "${EXTRA_INSTRUCTIONS:-}" should eq ""
    End

    It 'preserves special characters in instructions'
      cat > .gga << 'EOF'
PROVIDER="claude"
EXTRA_INSTRUCTIONS=$(cat <<'INSTRUCTIONS'
Check for:
- console.log() statements
- TODO comments
- API keys like "sk-xxxx"
INSTRUCTIONS
)
EOF
      # shellcheck source=/dev/null
      source .gga
      The variable EXTRA_INSTRUCTIONS should include "console.log()"
      The variable EXTRA_INSTRUCTIONS should include "TODO"
      The variable EXTRA_INSTRUCTIONS should include "sk-xxxx"
    End

    It 'counts lines correctly for multiline instructions'
      cat > .gga << 'EOF'
PROVIDER="claude"
EXTRA_INSTRUCTIONS=$(cat <<'INSTRUCTIONS'
Line 1
Line 2
Line 3
Line 4
Line 5
INSTRUCTIONS
)
EOF
      # shellcheck source=/dev/null
      source .gga
      line_count=$(echo "$EXTRA_INSTRUCTIONS" | wc -l | xargs)
      The value "$line_count" should eq "5"
    End
  End

  Describe 'build_prompt() with EXTRA_INSTRUCTIONS'
    # Source the main gga script functions
    # We need to extract build_prompt for testing
    
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR" || exit 1
      
      # Define build_prompt inline for testing (mirrors bin/gga)
      build_prompt() {
        local rules="$1"
        local files="$2"
        local extra="${EXTRA_INSTRUCTIONS:-}"

        cat << EOF
You are a code reviewer. Analyze the files below and validate they comply with the coding standards provided.
EOF

        if [[ -n "$extra" ]]; then
          cat << EOF

=== ADDITIONAL INSTRUCTIONS ===
$extra
=== END ADDITIONAL INSTRUCTIONS ===
EOF
        fi

        cat << EOF

=== CODING STANDARDS ===
$rules
=== END CODING STANDARDS ===

=== FILES TO REVIEW ===
EOF

        while IFS= read -r file; do
          if [[ -n "$file" && -f "$file" ]]; then
            echo ""
            echo "--- FILE: $file ---"
            cat "$file"
          fi
        done <<< "$files"

        cat << 'EOF'

=== END FILES ===

**IMPORTANT: Your response MUST start with exactly one of these lines:**
STATUS: PASSED
STATUS: FAILED

**If FAILED:** List each violation with:
- File name
- Line number (if applicable)
- Rule violated
- Description of the issue

**If PASSED:** Confirm all files comply with the coding standards.

**Start your response now with STATUS:**
EOF
      }
      export -f build_prompt
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'includes ADDITIONAL INSTRUCTIONS section when set'
      EXTRA_INSTRUCTIONS="Be strict about security."
      export EXTRA_INSTRUCTIONS
      echo "test" > test.ts
      
      result=$(build_prompt "Use const" "test.ts")
      
      The value "$result" should include "=== ADDITIONAL INSTRUCTIONS ==="
      The value "$result" should include "Be strict about security."
      The value "$result" should include "=== END ADDITIONAL INSTRUCTIONS ==="
    End

    It 'omits ADDITIONAL INSTRUCTIONS section when empty'
      EXTRA_INSTRUCTIONS=""
      export EXTRA_INSTRUCTIONS
      echo "test" > test.ts
      
      result=$(build_prompt "Use const" "test.ts")
      
      The value "$result" should not include "=== ADDITIONAL INSTRUCTIONS ==="
    End

    It 'omits ADDITIONAL INSTRUCTIONS section when unset'
      unset EXTRA_INSTRUCTIONS
      echo "test" > test.ts
      
      result=$(build_prompt "Use const" "test.ts")
      
      The value "$result" should not include "=== ADDITIONAL INSTRUCTIONS ==="
    End

    It 'places ADDITIONAL INSTRUCTIONS before CODING STANDARDS'
      EXTRA_INSTRUCTIONS="Check security first."
      export EXTRA_INSTRUCTIONS
      echo "test" > test.ts
      
      result=$(build_prompt "Use const" "test.ts")
      
      # Find positions
      extra_pos=$(echo "$result" | grep -n "ADDITIONAL INSTRUCTIONS" | head -1 | cut -d: -f1)
      coding_pos=$(echo "$result" | grep -n "CODING STANDARDS" | head -1 | cut -d: -f1)
      
      # ADDITIONAL should come before CODING
      The value "$extra_pos" should be less than "$coding_pos"
    End

    It 'preserves multiline instructions in prompt'
      EXTRA_INSTRUCTIONS=$'Line one.\nLine two.\nLine three.'
      export EXTRA_INSTRUCTIONS
      echo "test" > test.ts
      
      result=$(build_prompt "Use const" "test.ts")
      
      The value "$result" should include "Line one."
      The value "$result" should include "Line two."
      The value "$result" should include "Line three."
    End
  End
End
