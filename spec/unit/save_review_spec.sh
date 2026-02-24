# shellcheck shell=bash
# Tests for save_review_to_db() extracted function (bin/gga)
# This function lives in bin/gga, which can't be sourced directly (has set -e
# and main logic). We define the function here and source its dependencies.

Describe 'save_review_to_db()'
  Include "$LIB_DIR/config.sh"
  Include "$LIB_DIR/cache.sh"
  Include "$LIB_DIR/sqlite.sh"

  # Helper to check if sqlite3 is available
  no_sqlite3() {
    ! command -v sqlite3 &>/dev/null
  }

  # Define save_review_to_db exactly as in bin/gga (lines 760-795)
  save_review_to_db() {
    local review_status="$1"
    local files_to_review="$2"
    local result="$3"
    local provider="$4"
    local duration_ms="${5:-0}"

    # Only save if sqlite3 is available
    command -v sqlite3 &> /dev/null || return 0

    # Initialize database if needed
    load_env_config
    db_init > /dev/null 2>&1 || return 0

    # Get project info
    local project_path project_name git_branch git_commit
    project_path=$(pwd)
    project_name=$(basename "$project_path")
    git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    git_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "")

    # Build files list and count
    local files_list files_count
    files_list=$(echo "$files_to_review" | tr '\n' ',' | sed 's/,$//')
    files_count=$(echo "$files_to_review" | grep -c . || echo "0")

    # Generate diff hash for deduplication
    local diff_content diff_hash
    diff_content=$(git diff --cached 2>/dev/null || echo "")
    if [[ -n "$diff_content" ]]; then
      diff_hash=$(echo "$diff_content" | _compute_hash_stdin 2>/dev/null || echo "")
    else
      # Empty diff: generate unique hash to avoid collision (all empty diffs
      # would otherwise share the same hash, causing silent upsert overwrites)
      diff_hash=$(echo "empty-${project_path}-${git_branch}-${git_commit}-$(date +%s%N)-$$" \
        | _compute_hash_stdin 2>/dev/null || echo "")
    fi

    # Save to database
    db_save_review "$project_path" "$project_name" "$git_branch" "$git_commit" \
      "$files_list" "$files_count" "$diff_content" "$diff_hash" \
      "$result" "$review_status" "$provider" "" "$duration_ms" 2>/dev/null || true
  }

  Skip if "sqlite3 not installed" no_sqlite3

  setup() {
    TEMP_DIR=$(mktemp -d)
    export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
    # Create a git repo so git commands work
    cd "$TEMP_DIR"
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "hello" > file.txt
    git add file.txt
    git commit -m "init" --quiet
  }

  cleanup() {
    cd /
    rm -rf "$TEMP_DIR"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  Describe 'basic save and retrieve'
    It 'saves a PASSED review to the database'
      When call save_review_to_db "PASSED" "src/app.ts" "STATUS: PASSED" "gemini" "1500"
      The status should be success
      The path "$GGA_DB_PATH" should be file
    End

    It 'saves review with correct status'
      save_review_to_db "PASSED" "src/app.ts" "STATUS: PASSED" "gemini" "1500"

      When call db_get_reviews 1
      The output should include "PASSED"
    End

    It 'saves review with correct provider'
      save_review_to_db "FAILED" "src/app.ts" "STATUS: FAILED - violations" "claude" "2000"

      When call db_get_reviews 1
      The output should include "claude"
    End

    It 'saves review with correct project name'
      save_review_to_db "PASSED" "src/app.ts" "STATUS: PASSED" "gemini" "500"

      When call db_get_reviews 1
      # project_name is basename of pwd, which is the temp dir name
      The output should include "$(basename "$TEMP_DIR")"
    End
  End

  Describe 'multi-file reviews'
    It 'stores comma-separated file list'
      local files
      files=$(printf 'src/app.ts\nsrc/utils.ts\nsrc/main.ts')
      save_review_to_db "PASSED" "$files" "STATUS: PASSED" "gemini" "1000"

      When call sqlite3 "$GGA_DB_PATH" "SELECT files FROM reviews LIMIT 1;"
      The output should include "src/app.ts"
      The output should include "src/utils.ts"
    End

    It 'stores correct file count'
      local files
      files=$(printf 'a.ts\nb.ts\nc.ts')
      save_review_to_db "PASSED" "$files" "STATUS: PASSED" "gemini" "1000"

      When call sqlite3 "$GGA_DB_PATH" "SELECT files_count FROM reviews LIMIT 1;"
      The output should equal "3"
    End
  End

  Describe 'deduplication via diff_hash'
    It 'generates a diff_hash from staged changes'
      # Stage a change so git diff --cached has content
      echo "modified" > file.txt
      git add file.txt

      save_review_to_db "PASSED" "file.txt" "STATUS: PASSED" "gemini" "1000"

      When call sqlite3 "$GGA_DB_PATH" "SELECT diff_hash FROM reviews LIMIT 1;"
      The output should not equal ""
      The length of output should equal 64
    End

    It 'upserts review with same diff_hash'
      echo "change" > file.txt
      git add file.txt

      save_review_to_db "FAILED" "file.txt" "First review" "gemini" "1000"
      save_review_to_db "PASSED" "file.txt" "Second review" "claude" "2000"

      When call sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM reviews;"
      The output should equal "1"
    End

    It 'updates status on upsert'
      echo "change" > file.txt
      git add file.txt

      save_review_to_db "FAILED" "file.txt" "First" "gemini" "1000"
      save_review_to_db "PASSED" "file.txt" "Second" "claude" "2000"

      When call sqlite3 "$GGA_DB_PATH" "SELECT status FROM reviews LIMIT 1;"
      The output should equal "PASSED"
    End
  End

  Describe 'git metadata'
    It 'captures current branch'
      save_review_to_db "PASSED" "file.txt" "STATUS: PASSED" "gemini" "500"

      When call sqlite3 "$GGA_DB_PATH" "SELECT git_branch FROM reviews LIMIT 1;"
      # In a fresh git init the default branch is main or master
      The output should be present
    End

    It 'captures short commit hash'
      save_review_to_db "PASSED" "file.txt" "STATUS: PASSED" "gemini" "500"

      When call sqlite3 "$GGA_DB_PATH" "SELECT git_commit FROM reviews LIMIT 1;"
      The output should be present
      The length of output should equal 7
    End
  End

  Describe 'graceful degradation'
    It 'succeeds silently when sqlite3 is not in PATH'
      # Override command to simulate missing sqlite3
      command() {
        if [[ "$2" == "sqlite3" ]]; then
          return 1
        fi
        builtin command "$@"
      }

      When call save_review_to_db "PASSED" "file.txt" "STATUS: PASSED" "gemini" "500"
      The status should be success
    End

    It 'succeeds when db_init fails'
      # Override db_init to fail
      db_init() { return 1; }

      When call save_review_to_db "PASSED" "file.txt" "STATUS: PASSED" "gemini" "500"
      The status should be success
    End

    It 'uses default duration_ms of 0 when not provided'
      save_review_to_db "PASSED" "file.txt" "STATUS: PASSED" "gemini"

      When call sqlite3 "$GGA_DB_PATH" "SELECT duration_ms FROM reviews LIMIT 1;"
      The output should equal "0"
    End
  End

  Describe 'special characters in review content'
    It 'handles single quotes in result text'
      save_review_to_db "PASSED" "file.txt" "It's a great review: don't worry" "gemini" "500"

      When call db_get_reviews 1
      The output should include "great review"
    End

    It 'handles double quotes in result text'
      save_review_to_db "PASSED" "file.txt" 'Found "console.log" in code' "gemini" "500"

      When call db_get_reviews 1
      The output should include "console.log"
    End
  End
End
