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

  Describe 'db_get_review()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      # Insert test data
      db_save_review "/path1" "project1" "main" "abc123" \
        "auth.ts,login.ts" 2 "diff content here" "hash1" \
        "Security issue found in auth" "FAILED" "claude" "claude-3" 1500
      db_save_review "/path2" "project2" "dev" "def456" \
        "api.ts" 1 "api diff" "hash2" \
        "All good" "PASSED" "gemini" "" 1000
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns single review by ID'
      When call db_get_review 1
      The output should include "project1"
      The output should include "FAILED"
      The output should include "auth.ts"
    End

    It 'returns correct review for second ID'
      When call db_get_review 2
      The output should include "project2"
      The output should include "PASSED"
      The output should include "api.ts"
    End

    It 'returns empty array for non-existent ID'
      When call db_get_review 999
      The output should eq "[]"
    End

    It 'returns full review data including diff_content'
      When call db_get_review 1
      The output should include "diff content here"
      The output should include "Security issue found"
    End
  End

  Describe 'db_search_by_status()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      # Insert test data with different statuses
      db_save_review "/p1" "auth-service" "main" "a1" \
        "auth.ts" 1 "d1" "h1" "Passed review" "PASSED" "claude" "" 100
      db_save_review "/p2" "api-service" "main" "a2" \
        "api.ts" 1 "d2" "h2" "Found issues" "FAILED" "claude" "" 200
      db_save_review "/p3" "db-service" "main" "a3" \
        "db.ts" 1 "d3" "h3" "Also passed" "PASSED" "gemini" "" 300
      db_save_review "/p4" "error-service" "main" "a4" \
        "error.ts" 1 "d4" "h4" "Error occurred" "ERROR" "claude" "" 400
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns only PASSED reviews'
      When call db_search_by_status "PASSED"
      The output should include "auth-service"
      The output should include "db-service"
      The output should not include "api-service"
      The output should not include "error-service"
    End

    It 'returns only FAILED reviews'
      When call db_search_by_status "FAILED"
      The output should include "api-service"
      The output should not include "auth-service"
      The output should not include "db-service"
    End

    It 'returns only ERROR reviews'
      When call db_search_by_status "ERROR"
      The output should include "error-service"
      The output should not include "auth-service"
    End

    It 'respects limit parameter'
      When call db_search_by_status "PASSED" 1
      The status should be success
      The output should be defined
    End

    It 'returns empty array for status with no matches'
      When call db_search_by_status "UNKNOWN"
      The output should eq "[]"
    End
  End

  Describe 'db_stats_by_project()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      # Insert test data for multiple projects
      db_save_review "/p1" "frontend" "main" "a1" "f.ts" 1 "d" "h1" "r" "PASSED" "claude" "" 100
      db_save_review "/p2" "frontend" "main" "a2" "f.ts" 1 "d" "h2" "r" "PASSED" "claude" "" 200
      db_save_review "/p3" "frontend" "main" "a3" "f.ts" 1 "d" "h3" "r" "FAILED" "claude" "" 300
      db_save_review "/p4" "backend" "main" "a4" "f.ts" 1 "d" "h4" "r" "PASSED" "gemini" "" 400
      db_save_review "/p5" "backend" "main" "a5" "f.ts" 1 "d" "h5" "r" "FAILED" "gemini" "" 500
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns stats grouped by project'
      When call db_stats_by_project
      The output should include "frontend"
      The output should include "backend"
    End

    It 'includes review counts per project'
      When call db_stats_by_project
      The output should include "review_count"
    End

    It 'includes passed/failed counts'
      When call db_stats_by_project
      The output should include "passed"
      The output should include "failed"
    End

    It 'returns JSON format'
      When call db_stats_by_project
      The output should start with "["
    End
  End

  Describe 'db_cleanup()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      # Insert many reviews for same project
      local i
      for i in 1 2 3 4 5; do
        db_save_review "/p$i" "project-a" "main" "a$i" "f.ts" 1 "d" "h$i" "r" "PASSED" "claude" "" 100
      done
      # Insert reviews for another project
      for i in 6 7 8; do
        db_save_review "/p$i" "project-b" "main" "a$i" "f.ts" 1 "d" "h$i" "r" "PASSED" "claude" "" 100
      done
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'keeps specified number of reviews per project'
      # Before cleanup: 5 reviews for project-a, 3 for project-b
      count_before=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM reviews;")
      Assert [ "$count_before" = "8" ]

      When call db_cleanup 2
      The status should be success

      # After cleanup: 2 reviews for project-a, 2 for project-b
      count_after=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM reviews;")
      Assert [ "$count_after" = "4" ]
    End

    It 'keeps most recent reviews'
      db_cleanup 1
      # Should keep the last review for each project
      count=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM reviews;")
      The value "$count" should eq "2"
    End

    It 'does nothing when keep is larger than total'
      When call db_cleanup 100
      The status should be success
      count=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM reviews;")
      The value "$count" should eq "8"
    End

    It 'uses default keep value of 100'
      When call db_cleanup
      The status should be success
      # With only 8 reviews, nothing should be deleted
      count=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM reviews;")
      The value "$count" should eq "8"
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
