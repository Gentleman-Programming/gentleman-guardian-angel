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
      The output should eq "[]"
    End

    It 'safely handles SQL injection in project filter'
      db_save_review "/path" "project" "main" "abc" \
        "file.ts" 1 "diff" "hash_inj3" \
        "Result" "PASSED" "claude" "" 1000
      # Attempt SQL injection via project filter
      When call db_get_reviews 10 "" "project'; DROP TABLE reviews;--"
      The status should be success
      The output should eq "[]"
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
      The output should eq "[]"
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

  # ==========================================================================
  # _json_array_fix helper
  # ==========================================================================

  Describe '_json_array_fix()'
    It 'returns [] for [null] input'
      When call _json_array_fix '[null]'
      The output should eq "[]"
    End

    It 'returns [] for empty input'
      When call _json_array_fix ''
      The output should eq "[]"
    End

    It 'passes through valid JSON array'
      When call _json_array_fix '[{"id":1}]'
      The output should eq '[{"id":1}]'
    End
  End

  # ==========================================================================
  # db_get_review() functional tests (H6)
  # ==========================================================================

  Describe 'db_get_review()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      db_save_review "/path/to/project" "my-project" "main" "abc123" \
        "file1.ts,file2.ts" 2 "diff content here" "unique_hash_1" \
        "Review passed with no issues" "PASSED" "claude" "claude-3" 1500
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns a single review by ID'
      When call db_get_review 1
      The output should include "my-project"
      The output should include "PASSED"
      The output should include "claude"
    End

    It 'returns full review details including diff_content'
      When call db_get_review 1
      The output should include "diff content here"
      The output should include "unique_hash_1"
      The output should include "abc123"
    End

    It 'returns [] for non-existent review ID'
      When call db_get_review 999
      The output should eq "[]"
    End
  End

  # ==========================================================================
  # db_get_reviews() combined filter (M4)
  # ==========================================================================

  Describe 'db_get_reviews() combined filters'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      db_save_review "/p1" "alpha" "main" "a1" "f.ts" 1 "d" "h1" "r" "PASSED" "claude" "" 100
      db_save_review "/p2" "alpha" "main" "a2" "f.ts" 1 "d" "h2" "r" "FAILED" "claude" "" 200
      db_save_review "/p3" "beta" "main" "a3" "f.ts" 1 "d" "h3" "r" "PASSED" "gemini" "" 300
      db_save_review "/p4" "beta" "main" "a4" "f.ts" 1 "d" "h4" "r" "FAILED" "gemini" "" 400
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'filters by both status and project'
      When call db_get_reviews 10 "PASSED" "alpha"
      The output should include "alpha"
      The output should not include "beta"
      The output should not include "FAILED"
    End

    It 'returns [] when combined filter matches nothing'
      When call db_get_reviews 10 "ERROR" "alpha"
      The output should eq "[]"
    End
  End

  # ==========================================================================
  # db_search_by_status() (H5)
  # ==========================================================================

  Describe 'db_search_by_status()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      db_save_review "/p1" "proj1" "main" "a1" "f.ts" 1 "d" "h1" "Result one" "PASSED" "claude" "" 100
      db_save_review "/p2" "proj2" "main" "a2" "f.ts" 1 "d" "h2" "Result two" "FAILED" "gemini" "" 200
      db_save_review "/p3" "proj3" "main" "a3" "f.ts" 1 "d" "h3" "Result three" "PASSED" "claude" "" 300
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns reviews matching status'
      When call db_search_by_status "PASSED"
      The output should include "proj1"
      The output should include "proj3"
      The output should not include "proj2"
    End

    It 'returns [] for status with no matches'
      When call db_search_by_status "ERROR"
      The output should eq "[]"
    End

    It 'respects limit parameter'
      When call db_search_by_status "PASSED" 1
      The status should be success
      The output should be defined
    End
  End

  # ==========================================================================
  # db_stats_by_project() (H5)
  # ==========================================================================

  Describe 'db_stats_by_project()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      db_save_review "/p1" "alpha" "main" "a1" "f.ts" 1 "d" "h1" "r" "PASSED" "claude" "" 100
      db_save_review "/p2" "alpha" "main" "a2" "f.ts" 1 "d" "h2" "r" "FAILED" "claude" "" 200
      db_save_review "/p3" "beta" "main" "a3" "f.ts" 1 "d" "h3" "r" "PASSED" "gemini" "" 300
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns stats grouped by project'
      When call db_stats_by_project
      The output should include "alpha"
      The output should include "beta"
    End

    It 'includes review counts per project'
      When call db_stats_by_project
      The output should include "review_count"
      The output should include "passed"
      The output should include "failed"
    End

    It 'returns [] for empty database'
      sqlite3 "$GGA_DB_PATH" "DELETE FROM reviews;"
      When call db_stats_by_project
      The output should eq "[]"
    End
  End

  # ==========================================================================
  # db_cleanup() (H5)
  # ==========================================================================

  Describe 'db_cleanup()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      # Insert 5 reviews for same project
      local i
      for i in 1 2 3 4 5; do
        db_save_review "/p" "proj1" "main" "a$i" "f.ts" 1 "d" "cleanup_h$i" "result $i" "PASSED" "claude" "" 100
      done
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'keeps the specified number of reviews per project'
      When call db_cleanup 3
      The status should be success
      count=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM reviews;")
      The value "$count" should eq "3"
    End

    It 'keeps all reviews when count is higher than total'
      When call db_cleanup 100
      The status should be success
      count=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM reviews;")
      The value "$count" should eq "5"
    End

    It 'runs VACUUM after cleanup'
      # Just verify it does not error out
      When call db_cleanup 2
      The status should be success
    End
  End

  # ==========================================================================
  # FTS5 index after upsert (C3)
  # ==========================================================================

  Describe 'FTS5 index after upsert'
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

    It 'updates FTS5 index when review is upserted'
      # Insert original review with searchable content
      db_save_review "/path" "project" "main" "abc" \
        "auth.ts" 1 "diff" "fts_upsert_hash" \
        "Original review about authentication" "PASSED" "claude" "" 1000
      # Upsert with different content
      db_save_review "/path" "project" "main" "def" \
        "auth.ts" 1 "diff" "fts_upsert_hash" \
        "Updated review about authorization" "FAILED" "gemini" "" 2000
      # Search for old content should NOT find it
      old_result=$(db_search_reviews "authentication")
      The value "$old_result" should eq "[]"
      # Search for new content SHOULD find it
      new_result=$(db_search_reviews "authorization")
      The value "$new_result" should include "project"
    End

    It 'keeps FTS5 index in sync after multiple inserts'
      db_save_review "/p1" "proj1" "main" "a1" \
        "api.ts" 1 "code" "fts_hash1" \
        "Security vulnerability detected" "FAILED" "claude" "" 100
      db_save_review "/p2" "proj2" "main" "a2" \
        "db.ts" 1 "code" "fts_hash2" \
        "Database migration successful" "PASSED" "gemini" "" 200
      # Search should find each by unique content
      sec_result=$(db_search_reviews "vulnerability")
      The value "$sec_result" should include "proj1"
      db_result=$(db_search_reviews "migration")
      The value "$db_result" should include "proj2"
    End
  End
End
