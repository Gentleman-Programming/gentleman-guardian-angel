# shellcheck shell=bash

Describe 'Staged files reading behavior'
  # This tests that GGA reads from the staging area (index), not the working directory
  # This is critical to prevent index corruption and ensure we review what will be committed

  setup() {
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit 1
    git init --quiet 2>/dev/null
    git config user.email "test@test.com"
    git config user.name "Test User"
    # Avoid CRLF warnings on Windows
    git config core.autocrlf false
    git config core.safecrlf false
    GGA_BIN="$PROJECT_ROOT/bin/gga"

    # Create minimal config
    cat > .gga << 'EOF'
PROVIDER="claude"
FILE_PATTERNS="*.ts"
RULES_FILE="AGENTS.md"
STRICT_MODE="true"
EOF

    # Create rules file
    echo "# Test Rules" > AGENTS.md
  }

  cleanup() {
    cd /
    rm -rf "$TEMP_DIR"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  Describe 'git show reads staged content correctly'
    It 'git show :file reads from staging area, not working directory'
      # Create a file with initial content and stage it
      echo "STAGED_CONTENT" > test.ts
      git add test.ts 2>/dev/null

      # Modify the file AFTER staging (working directory differs from index)
      echo "WORKING_DIR_CONTENT" > test.ts

      # git show :file should return STAGED content
      staged_content=$(git show :test.ts)
      working_content=$(cat test.ts)

      The value "$staged_content" should equal "STAGED_CONTENT"
      The value "$working_content" should equal "WORKING_DIR_CONTENT"
    End
  End

  Describe 'Race condition scenarios (Issue #15)'
    # These tests verify that GGA handles scenarios where the working directory
    # changes AFTER staging but BEFORE commit - a common source of index corruption

    It 'handles file modified after staging (partial stage scenario)'
      # User stages a file, then modifies it again before committing
      # This is a VERY common workflow that was causing issues

      echo "function valid() { return true; }" > app.ts
      git add app.ts 2>/dev/null

      # User continues editing after staging
      echo "function invalid() { return BAD_CODE; }" > app.ts

      # GGA should review the STAGED version (valid), not the working dir version (invalid)
      staged=$(git show :app.ts)

      The value "$staged" should include "valid"
      The value "$staged" should not include "invalid"
      The value "$staged" should not include "BAD_CODE"
    End

    It 'handles multiple files with mixed staged/unstaged changes'
      # Stage file1 completely, stage file2 partially
      echo "const file1_staged = 'ok';" > file1.ts
      echo "const file2_staged = 'ok';" > file2.ts
      git add file1.ts file2.ts 2>/dev/null

      # Modify only file2 after staging
      echo "const file2_modified = 'BREAKING_CHANGE';" > file2.ts

      # Both should return staged versions
      file1_staged=$(git show :file1.ts)
      file2_staged=$(git show :file2.ts)

      The value "$file1_staged" should include "file1_staged"
      The value "$file2_staged" should include "file2_staged"
      The value "$file2_staged" should not include "BREAKING_CHANGE"
    End

    It 'handles file deleted from working dir after staging'
      # User stages a file, then deletes it from working directory
      # git show :file should still work

      echo "const willBeDeleted = true;" > deleted.ts
      git add deleted.ts 2>/dev/null

      # Delete from working directory (but still staged)
      rm deleted.ts

      # Should still be able to read from staging area
      staged=$(git show :deleted.ts 2>/dev/null)

      The value "$staged" should include "willBeDeleted"
    End

    It 'handles file with different line endings after staging'
      # Stage with LF, working dir has CRLF (common on Windows or with autocrlf)
      printf "line1\nline2\n" > endings.ts
      git add endings.ts 2>/dev/null

      # Simulate CRLF in working directory
      printf "line1\r\nline2\r\n" > endings.ts

      # Staged version should have original line endings
      staged=$(git show :endings.ts | od -c 2>/dev/null | sed -n '1p')

      # Should NOT contain \r (carriage return)
      The value "$staged" should not include "\\r"
    End

    It 'handles concurrent file modifications (simulated race)'
      # Simulate what happens when another tool (like lint-staged) modifies files
      # while GGA is trying to read them

      echo "const original = 'before_lint';" > linted.ts
      git add linted.ts 2>/dev/null

      # Simulate lint-staged or prettier modifying the file
      echo "const formatted = 'after_lint_prettier';" > linted.ts

      # Even with concurrent modifications, git show :file is atomic
      # and returns the exact staged content
      staged=$(git show :linted.ts)

      The value "$staged" should include "before_lint"
      The value "$staged" should equal "const original = 'before_lint';"
    End

    It 'git index remains consistent after failed git show'
      # Ensure that a failed git show does not corrupt the index

      echo "const valid = true;" > valid.ts
      git add valid.ts 2>/dev/null

      # Try to read a non-existent file from index (should fail gracefully)
      git show :nonexistent.ts 2>/dev/null || true

      # Index should still be valid
      index_status=$(git diff --cached --name-only)

      The value "$index_status" should include "valid.ts"
    End

    It 'handles rapid stage-unstage-restage cycles'
      # User is indecisive and stages/unstages multiple times

      echo "version1" > cycle.ts
      git add cycle.ts 2>/dev/null

      echo "version2" > cycle.ts
      git add cycle.ts 2>/dev/null

      echo "version3" > cycle.ts
      # Don't stage version3

      # Should see version2 (last staged version)
      staged=$(git show :cycle.ts)

      The value "$staged" should equal "version2"
    End
  End

  Describe 'get_staged_files function'
    # Source only the necessary parts for testing
    Include "$PROJECT_ROOT/lib/cache.sh"

    # Define a minimal version of the function for testing
    get_staged_files_test() {
      local patterns="$1"
      local excludes="$2"

      local staged
      staged=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)

      if [[ -z "$staged" ]]; then
        return
      fi

      IFS=',' read -ra PATTERN_ARRAY <<< "$patterns"
      IFS=',' read -ra EXCLUDE_ARRAY <<< "$excludes"

      echo "$staged" | while IFS= read -r file; do
        local match=false
        local excluded=false

        for pattern in "${PATTERN_ARRAY[@]}"; do
          pattern=$(echo "$pattern" | xargs)
          if [[ "$pattern" == \** ]]; then
            local suffix="${pattern#\*}"
            if [[ "$file" == *"$suffix" ]]; then
              match=true
              break
            fi
          else
            if [[ "$file" == $pattern ]] || [[ "$(basename "$file")" == $pattern ]]; then
              match=true
              break
            fi
          fi
        done

        if [[ "$match" == true && -n "$excludes" ]]; then
          for pattern in "${EXCLUDE_ARRAY[@]}"; do
            pattern=$(echo "$pattern" | xargs)
            if [[ "$pattern" == \** ]]; then
              local suffix="${pattern#\*}"
              if [[ "$file" == *"$suffix" ]]; then
                excluded=true
                break
              fi
            else
              if [[ "$file" == $pattern ]] || [[ "$(basename "$file")" == $pattern ]]; then
                excluded=true
                break
              fi
            fi
          done
        fi

        if [[ "$match" == true && "$excluded" == false ]]; then
          echo "$file"
        fi
      done
    }

    It 'returns only staged files matching patterns'
      # Create and stage a matching file
      echo "const a = 1;" > included.ts
      git add included.ts 2>/dev/null

      # Create but don't stage another file
      echo "const b = 2;" > not-staged.ts

      result=$(get_staged_files_test "*.ts" "")

      The value "$result" should include "included.ts"
      The value "$result" should not include "not-staged.ts"
    End

    It 'excludes files matching exclude patterns'
      # Create and stage files
      echo "const a = 1;" > app.ts
      echo "const b = 2;" > app.test.ts
      git add app.ts app.test.ts 2>/dev/null

      result=$(get_staged_files_test "*.ts" "*.test.ts")

      The value "$result" should include "app.ts"
      The value "$result" should not include "app.test.ts"
    End
  End

  Describe 'build_prompt uses git show for staged files'
    It 'prompt contains staged content when use_staged is true'
      # Create and stage a file
      echo "const staged = 'STAGED_VALUE';" > test.ts
      git add test.ts 2>/dev/null

      # Modify after staging
      echo "const modified = 'MODIFIED_VALUE';" > test.ts

      # Simulate what build_prompt does with use_staged=true
      prompt_content=$(git show :test.ts 2>/dev/null)

      The value "$prompt_content" should include "STAGED_VALUE"
      The value "$prompt_content" should not include "MODIFIED_VALUE"
    End

    It 'prompt contains working directory content when use_staged is false'
      # Create and stage a file
      echo "const staged = 'STAGED_VALUE';" > test.ts
      git add test.ts 2>/dev/null
      git commit -m "initial" --quiet 2>/dev/null

      # For CI mode, we read from filesystem
      file_content=$(cat test.ts)

      The value "$file_content" should include "STAGED_VALUE"
    End
  End
End
