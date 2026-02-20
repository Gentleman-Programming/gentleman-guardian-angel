# shellcheck shell=bash

Describe 'review_insights'
  Include "$LIB_DIR/config.sh"
  Include "$LIB_DIR/sqlite.sh"

  no_sqlite3() {
    ! command -v sqlite3 &>/dev/null
  }

  # Helper: sqlite3 with Windows \r stripping for exact comparisons
  sqlite3_clean() {
    sqlite3 "$GGA_DB_PATH" "$1" | tr -d '\r'
  }

  Describe 'schema'
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

    It 'creates review_insights table'
      db_init >/dev/null
      When call sqlite3 "$GGA_DB_PATH" ".tables"
      The output should include "review_insights"
    End

    It 'creates insights_fts virtual table'
      db_init >/dev/null
      When call sqlite3 "$GGA_DB_PATH" ".tables"
      The output should include "insights_fts"
    End
  End

  Describe 'db_save_insight()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init >/dev/null
      # Create a review to reference
      db_save_review "/tmp/proj" "test-proj" "main" "abc123" \
        "auth.ts" 1 "diff content" "hash1" \
        "STATUS: FAILED\nIssue found" "FAILED" "mock" "" 100 2>/dev/null
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'saves a security insight'
      When call db_save_insight 1 "security" "SQL injection in query" "User input not escaped" "auth.ts:42" "Use parameterized queries" "high"
      The status should be success
    End

    It 'saves with valid type'
      db_save_insight 1 "bugfix" "Null check missing" "" "" "" "low" 2>/dev/null
      When call sqlite3_clean "SELECT type FROM review_insights WHERE review_id=1;"
      The output should eq "bugfix"
    End

    It 'defaults invalid type to pattern'
      db_save_insight 1 "invalid_type" "Some finding" "" "" "" "" 2>/dev/null
      When call sqlite3_clean "SELECT type FROM review_insights WHERE review_id=1;"
      The output should eq "pattern"
    End

    It 'defaults invalid severity to medium'
      db_save_insight 1 "security" "Finding" "" "" "" "invalid_sev" 2>/dev/null
      When call sqlite3_clean "SELECT severity FROM review_insights WHERE review_id=1;"
      The output should eq "medium"
    End
  End

  Describe 'db_get_insights()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init >/dev/null
      db_save_review "/tmp/proj" "test-proj" "main" "abc123" \
        "auth.ts" 1 "diff" "hash1" "STATUS: FAILED" "FAILED" "mock" "" 100 2>/dev/null
      db_save_insight 1 "security" "SQL injection" "Bad input" "auth.ts:42" "Use params" "critical" 2>/dev/null
      db_save_insight 1 "style" "Missing semicolon" "" "auth.ts:10" "" "low" 2>/dev/null
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns insights for a review'
      When call db_get_insights 1
      The output should include "SQL injection"
      The output should include "security"
    End

    It 'orders by severity (critical first)'
      When call db_get_insights 1
      The output should include "critical"
    End
  End

  Describe 'db_search_insights()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init >/dev/null
      db_save_review "/tmp/proj" "test-proj" "main" "abc123" \
        "auth.ts" 1 "diff" "hash1" "STATUS: FAILED" "FAILED" "mock" "" 100 2>/dev/null
      db_save_insight 1 "security" "SQL injection found" "Input not sanitized" "auth.ts" "Use prepared statements" "high" 2>/dev/null
      db_save_insight 1 "performance" "Slow query detected" "Missing index" "db.ts" "Add index" "medium" 2>/dev/null
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'searches insights by keyword'
      When call db_search_insights "injection"
      The output should include "SQL injection"
    End

    It 'returns empty for no matches'
      When call db_search_insights "nonexistent_xyz"
      The status should be success
    End
  End

  Describe 'extract_review_insights()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init >/dev/null
      db_save_review "/tmp/proj" "test-proj" "main" "abc123" \
        "auth.ts" 1 "diff" "hash1" "STATUS: FAILED" "FAILED" "mock" "" 100 2>/dev/null
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'extracts security type from review mentioning injection'
      extract_review_insights "STATUS: FAILED
Found SQL injection vulnerability in auth.ts:42
User input passed directly to query without sanitization" 1
      When call sqlite3_clean "SELECT type FROM review_insights WHERE review_id=1;"
      The output should eq "security"
    End

    It 'extracts bugfix type from review mentioning errors'
      extract_review_insights "STATUS: FAILED
Null reference error in handler.ts
Variable could be undefined at line 15" 1
      When call sqlite3_clean "SELECT type FROM review_insights WHERE review_id=1;"
      The output should eq "bugfix"
    End

    It 'extracts performance type'
      extract_review_insights "STATUS: FAILED
Slow database query without caching
Consider optimizing with an index" 1
      When call sqlite3_clean "SELECT type FROM review_insights WHERE review_id=1;"
      The output should eq "performance"
    End

    It 'extracts critical severity'
      extract_review_insights "STATUS: FAILED
Critical vulnerability found: XSS injection possible" 1
      When call sqlite3_clean "SELECT severity FROM review_insights WHERE review_id=1;"
      The output should eq "critical"
    End

    It 'does nothing for empty result'
      When call extract_review_insights "" 1
      The status should be success
    End

    It 'extracts file paths from review'
      extract_review_insights "STATUS: FAILED
Issue in src/auth.ts:42 and utils/db.py" 1
      When call sqlite3 "$GGA_DB_PATH" "SELECT file_path FROM review_insights WHERE review_id=1;"
      The output should include "auth.ts"
    End
  End

  Describe 'db_get_insight_summaries()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init >/dev/null
      db_save_review "/tmp/proj" "test-proj" "main" "abc123" \
        "auth.ts" 1 "diff" "hash1" "STATUS: FAILED" "FAILED" "mock" "" 100 2>/dev/null
      db_save_insight 1 "security" "SQL injection" "" "auth.ts" "" "critical" 2>/dev/null
      db_save_insight 1 "style" "Formatting issue" "" "auth.ts" "" "low" 2>/dev/null
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns pipe-separated compact summaries'
      When call db_get_insight_summaries "1"
      The output should include "security"
      The output should include "SQL injection"
    End

    It 'orders critical first'
      When call db_get_insight_summaries "1"
      The line 1 of output should include "critical"
    End

    It 'returns empty for no review ids'
      When call db_get_insight_summaries ""
      The status should be success
    End
  End
End
