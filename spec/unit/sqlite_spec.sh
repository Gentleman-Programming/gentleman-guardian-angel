# shellcheck shell=bash

Describe 'sqlite.sh'
  Include "$LIB_DIR/config.sh"
  Include "$LIB_DIR/sqlite.sh"

  # Helper to check if sqlite3 is available
  no_sqlite3() {
    ! command -v sqlite3 &>/dev/null
  }

  Describe 'db_init()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'creates database file'
      When call db_init
      The status should be success
      The output should be defined
      The path "$GGA_DB_PATH" should be file
    End

    It 'creates reviews table'
      db_init > /dev/null
      result=$(sqlite3 "$GGA_DB_PATH" ".tables" 2>/dev/null)
      The value "$result" should include "reviews"
    End

    It 'creates reviews_fts virtual table'
      db_init > /dev/null
      result=$(sqlite3 "$GGA_DB_PATH" ".tables" 2>/dev/null)
      The value "$result" should include "reviews_fts"
    End

    It 'returns database path'
      When call db_init
      The output should eq "$GGA_DB_PATH"
    End
  End

  Describe 'db_save_review()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'inserts a review'
      db_save_review "/path/to/project" "my-project" "main" "abc123" \
        "file1.ts,file2.ts" 2 "diff content" "hash123" \
        "Review passed" "PASSED" "claude" "claude-3" 1500
      count=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM reviews;")
      The value "$count" should eq "1"
    End

    It 'stores correct status'
      db_save_review "/path" "project" "main" "abc" \
        "file.ts" 1 "diff" "hash1" \
        "Result" "FAILED" "gemini" "" 1000
      status=$(sqlite3 "$GGA_DB_PATH" "SELECT status FROM reviews WHERE id=1;")
      The value "$status" should eq "FAILED"
    End

    It 'handles single quotes in content'
      db_save_review "/path" "project" "main" "abc" \
        "file.ts" 1 "diff with 'quotes'" "hash2" \
        "Result with 'quotes'" "PASSED" "claude" "" 1000
      count=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM reviews;")
      The value "$count" should eq "1"
    End

    It 'replaces review with same diff_hash'
      db_save_review "/path" "project" "main" "abc" \
        "file.ts" 1 "diff" "same_hash" \
        "First result" "PASSED" "claude" "" 1000
      db_save_review "/path" "project" "main" "def" \
        "file.ts" 1 "diff" "same_hash" \
        "Second result" "FAILED" "claude" "" 2000
      count=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM reviews;")
      The value "$count" should eq "1"
    End
  End

  Describe 'db_get_reviews()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      # Insert test data
      db_save_review "/path1" "project1" "main" "abc1" \
        "file1.ts" 1 "diff1" "hash1" "Result 1" "PASSED" "claude" "" 1000
      db_save_review "/path2" "project2" "main" "abc2" \
        "file2.ts" 2 "diff2" "hash2" "Result 2" "FAILED" "gemini" "" 2000
      db_save_review "/path3" "project1" "dev" "abc3" \
        "file3.ts" 3 "diff3" "hash3" "Result 3" "PASSED" "claude" "" 3000
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns reviews as JSON'
      When call db_get_reviews 10
      The output should include "project1"
      The output should include "project2"
    End

    It 'respects limit parameter'
      When call db_get_reviews 1
      The status should be success
      The output should be defined
    End

    It 'filters by status'
      When call db_get_reviews 10 "PASSED"
      The output should include "project1"
      The output should not include "project2"
    End

    It 'filters by project'
      When call db_get_reviews 10 "" "project1"
      The output should include "project1"
      The output should not include "project2"
    End
  End

  Describe 'db_search_reviews()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      # Insert test data with searchable content
      db_save_review "/path1" "auth-service" "main" "abc1" \
        "auth.ts,login.ts" 2 "authentication code" "hash1" \
        "Found SQL injection vulnerability" "FAILED" "claude" "" 1000
      db_save_review "/path2" "api-service" "main" "abc2" \
        "api.ts" 1 "api endpoint code" "hash2" \
        "All endpoints validated" "PASSED" "gemini" "" 2000
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'finds reviews by file content'
      When call db_search_reviews "auth"
      The output should include "auth-service"
    End

    It 'finds reviews by result content'
      When call db_search_reviews "SQL injection"
      The output should include "auth-service"
    End

    It 'returns empty for no matches'
      When call db_search_reviews "nonexistent_term_xyz"
      The output should eq "[]"
    End
  End

  Describe 'db_stats()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      db_save_review "/p1" "proj1" "main" "a" "f.ts" 1 "d" "h1" "r" "PASSED" "claude" "" 100
      db_save_review "/p2" "proj1" "main" "b" "f.ts" 1 "d" "h2" "r" "PASSED" "claude" "" 200
      db_save_review "/p3" "proj2" "main" "c" "f.ts" 1 "d" "h3" "r" "FAILED" "claude" "" 300
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns review statistics'
      When call db_stats
      The output should include "3"  # total reviews
    End
  End

  Describe 'db_check()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns ok for valid database'
      When call db_check
      The output should include "ok"
    End
  End
End
