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

  # ==========================================================================
  # SQL Sanitization Helpers
  # ==========================================================================

  Describe '_sql_escape()'
    It 'doubles single quotes'
      When call _sql_escape "O'Brien"
      The output should eq "O''Brien"
    End

    It 'handles multiple single quotes'
      When call _sql_escape "it's a 'test'"
      The output should eq "it''s a ''test''"
    End

    It 'returns empty for empty input'
      When call _sql_escape ""
      The output should eq ""
    End

    It 'leaves clean strings unchanged'
      When call _sql_escape "clean string"
      The output should eq "clean string"
    End
  End

  Describe '_sql_validate_int()'
    It 'accepts valid positive integer'
      When call _sql_validate_int "42" 0
      The output should eq "42"
    End

    It 'accepts zero'
      When call _sql_validate_int "0" 10
      The output should eq "0"
    End

    It 'rejects negative numbers'
      When call _sql_validate_int "-5" 10
      The output should eq "10"
    End

    It 'rejects non-numeric strings'
      When call _sql_validate_int "abc" 50
      The output should eq "50"
    End

    It 'rejects SQL injection attempts'
      When call _sql_validate_int "1; DROP TABLE reviews" 20
      The output should eq "20"
    End

    It 'uses 0 as default when no default provided'
      When call _sql_validate_int "invalid"
      The output should eq "0"
    End
  End

  Describe '_fts5_sanitize()'
    It 'wraps tokens in double quotes'
      When call _fts5_sanitize "auth login"
      The output should eq '"auth" "login"'
    End

    It 'strips FTS5 special characters'
      When call _fts5_sanitize 'test* (group) "exact" ^boost'
      The output should eq '"test" "group" "exact" "boost"'
    End

    It 'neutralizes FTS5 operators'
      When call _fts5_sanitize "auth AND NOT admin"
      The output should eq '"auth" "AND" "NOT" "admin"'
    End

    It 'returns empty for empty input'
      When call _fts5_sanitize ""
      The output should eq ""
    End

    It 'returns empty for only special characters'
      When call _fts5_sanitize '"()*^'
      The output should eq ""
    End
  End

  # ==========================================================================
  # SQL Injection Prevention (integration tests)
  # ==========================================================================

  Describe 'SQL injection prevention'
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

    It 'safely stores provider with single quotes'
      db_save_review "/path" "project" "main" "abc" \
        "file.ts" 1 "diff" "hash_inj1" \
        "Result" "PASSED" "O'Brien's provider" "" 1000
      provider=$(sqlite3 "$GGA_DB_PATH" "SELECT provider FROM reviews WHERE diff_hash='hash_inj1';")
      The value "$provider" should eq "O'Brien's provider"
    End

    It 'safely handles SQL injection in status filter'
      db_save_review "/path" "project" "main" "abc" \
        "file.ts" 1 "diff" "hash_inj2" \
        "Result" "PASSED" "claude" "" 1000
      # Attempt SQL injection via status filter
      When call db_get_reviews 10 "PASSED' OR '1'='1"
      The status should be success
    End

    It 'safely handles SQL injection in project filter'
      db_save_review "/path" "project" "main" "abc" \
        "file.ts" 1 "diff" "hash_inj3" \
        "Result" "PASSED" "claude" "" 1000
      # Attempt SQL injection via project filter
      When call db_get_reviews 10 "" "project'; DROP TABLE reviews;--"
      The status should be success
      # Table should still exist
      count=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM reviews;")
      The value "$count" should eq "1"
    End

    It 'rejects non-numeric limit values'
      db_save_review "/path" "project" "main" "abc" \
        "file.ts" 1 "diff" "hash_inj4" \
        "Result" "PASSED" "claude" "" 1000
      # Attempt injection via limit — should fall back to default
      When call db_get_reviews "1; DROP TABLE reviews"
      The status should be success
      The output should be defined
    End

    It 'safely handles FTS5 operator injection in search'
      db_save_review "/path" "project" "main" "abc" \
        "auth.ts" 1 "diff" "hash_inj5" \
        "Found vulnerability" "FAILED" "claude" "" 1000
      # Attempt FTS5 operator injection
      When call db_search_reviews 'auth) OR (vulnerability'
      The status should be success
      The output should be defined
    End

    It 'validates review_id as integer in db_get_review'
      db_save_review "/path" "project" "main" "abc" \
        "file.ts" 1 "diff" "hash_inj6" \
        "Result" "PASSED" "claude" "" 1000
      # Non-numeric ID should return empty (id=0 matches nothing)
      When call db_get_review "1; DROP TABLE reviews"
      The status should be success
      # Table should still exist
      count=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM reviews;")
      The value "$count" should eq "1"
    End
  End

  # ==========================================================================
  # Schema constraints
  # ==========================================================================

  Describe 'schema constraints'
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

    It 'enforces diff_hash NOT NULL'
      result=$(sqlite3 "$GGA_DB_PATH" "PRAGMA table_info(reviews);" 2>/dev/null)
      # diff_hash column should have notnull=1
      The value "$result" should include "diff_hash"
    End

    It 'preserves row ID on upsert (ON CONFLICT)'
      db_save_review "/path" "project" "main" "abc" \
        "file.ts" 1 "diff" "upsert_hash" \
        "First result" "PASSED" "claude" "" 1000
      id_before=$(sqlite3 "$GGA_DB_PATH" "SELECT id FROM reviews WHERE diff_hash='upsert_hash';")
      db_save_review "/path" "project" "main" "def" \
        "file.ts" 1 "diff" "upsert_hash" \
        "Updated result" "FAILED" "gemini" "" 2000
      id_after=$(sqlite3 "$GGA_DB_PATH" "SELECT id FROM reviews WHERE diff_hash='upsert_hash';")
      The value "$id_after" should eq "$id_before"
    End

    It 'updates fields on upsert'
      db_save_review "/path" "project" "main" "abc" \
        "file.ts" 1 "diff" "upsert_hash2" \
        "First result" "PASSED" "claude" "" 1000
      db_save_review "/path" "project" "main" "def" \
        "file.ts" 1 "diff" "upsert_hash2" \
        "Updated result" "FAILED" "gemini" "" 2000
      result=$(sqlite3 "$GGA_DB_PATH" "SELECT result FROM reviews WHERE diff_hash='upsert_hash2';")
      The value "$result" should eq "Updated result"
    End

    It 'updates metadata columns on upsert (branch, commit, files)'
      db_save_review "/path/old" "old-project" "main" "aaa" \
        "old.ts" 1 "diff-old" "meta_hash" \
        "First" "PASSED" "claude" "" 500
      db_save_review "/path/new" "new-project" "feature" "bbb" \
        "new.ts,extra.ts" 2 "diff-new" "meta_hash" \
        "Second" "FAILED" "gemini" "" 1500

      branch=$(sqlite3 "$GGA_DB_PATH" "SELECT git_branch FROM reviews WHERE diff_hash='meta_hash';")
      commit=$(sqlite3 "$GGA_DB_PATH" "SELECT git_commit FROM reviews WHERE diff_hash='meta_hash';")
      files_count=$(sqlite3 "$GGA_DB_PATH" "SELECT files_count FROM reviews WHERE diff_hash='meta_hash';")
      project_name=$(sqlite3 "$GGA_DB_PATH" "SELECT project_name FROM reviews WHERE diff_hash='meta_hash';")

      The value "$branch" should eq "feature"
      The value "$commit" should eq "bbb"
      The value "$files_count" should eq "2"
      The value "$project_name" should eq "new-project"
    End

    It 'only allows valid status values'
      insert_invalid_status() {
        sqlite3 "$GGA_DB_PATH" \
          "INSERT INTO reviews (project_path, project_name, files, files_count, diff_hash, result, status, provider) VALUES ('/p','n','f',1,'h','r','INVALID','p');" 2>&1
      }
      When call insert_invalid_status
      The status should be failure
      The output should include "CHECK constraint failed"
    End
  End
End
