# shellcheck shell=bash

Describe 'Structured Insights'
  Include "$LIB_DIR/config.sh"
  Include "$LIB_DIR/sqlite.sh"

  no_sqlite3() {
    ! command -v sqlite3 &>/dev/null
  }

  Describe 'insights schema'
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

    It 'creates review_insights table'
      result=$(sqlite3 "$GGA_DB_PATH" ".tables" 2>/dev/null)
      The value "$result" should include "review_insights"
    End

    It 'creates insights_fts virtual table'
      result=$(sqlite3 "$GGA_DB_PATH" ".tables" 2>/dev/null)
      The value "$result" should include "insights_fts"
    End

    It 'creates insight indexes'
      result=$(sqlite3 "$GGA_DB_PATH" ".indexes review_insights" 2>/dev/null)
      The value "$result" should include "idx_insights_type"
    End
  End

  Describe 'db_save_insight()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      # Insert a review to reference
      sqlite3 "$GGA_DB_PATH" "INSERT INTO reviews (project_path, project_name, git_branch, git_commit, files, files_count, diff_content, diff_hash, result, status, provider, duration_ms) VALUES ('/test', 'test-project', 'main', 'abc', 'f.ts', 1, 'diff', 'hash1', 'result', 'PASSED', 'claude', 100);"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'saves a basic insight'
      When call db_save_insight 1 "security" "SQL injection found" "" "auth.ts" "" "high"
      The status should be success
    End

    It 'stores correct type'
      db_save_insight 1 "bugfix" "Null pointer fix" "" "" "" "medium"
      result=$(sqlite3 "$GGA_DB_PATH" "SELECT type FROM review_insights WHERE id = 1;")
      The value "$result" should eq "bugfix"
    End

    It 'stores correct severity'
      db_save_insight 1 "security" "XSS vulnerability" "" "" "" "critical"
      result=$(sqlite3 "$GGA_DB_PATH" "SELECT severity FROM review_insights WHERE id = 1;")
      The value "$result" should eq "critical"
    End

    It 'rejects invalid review_id'
      When call db_save_insight 0 "bugfix" "test" "" "" "" "low"
      The status should be failure
      The stderr should include "invalid"
    End

    It 'saves all insight types'
      db_save_insight 1 "bugfix" "Fix 1" "" "" "" "low"
      db_save_insight 1 "security" "Sec 1" "" "" "" "high"
      db_save_insight 1 "pattern" "Pat 1" "" "" "" "medium"
      db_save_insight 1 "decision" "Dec 1" "" "" "" "medium"
      db_save_insight 1 "style" "Sty 1" "" "" "" "low"
      db_save_insight 1 "performance" "Perf 1" "" "" "" "medium"
      count=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM review_insights;")
      The value "$count" should eq "6"
    End
  End

  Describe 'db_get_insights()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      sqlite3 "$GGA_DB_PATH" "INSERT INTO reviews (project_path, project_name, git_branch, git_commit, files, files_count, diff_content, diff_hash, result, status, provider, duration_ms) VALUES ('/test', 'test-project', 'main', 'abc', 'f.ts', 1, 'diff', 'hash2', 'result', 'PASSED', 'claude', 100);"
      # Insert insights with different severities
      db_save_insight 1 "bugfix" "Low bug" "" "" "" "low"
      db_save_insight 1 "security" "Critical vuln" "" "" "" "critical"
      db_save_insight 1 "pattern" "Medium pattern" "" "" "" "medium"
      db_save_insight 1 "performance" "High perf" "" "" "" "high"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns insights for a review'
      When call db_get_insights 1
      The status should be success
      The output should include '"type"'
      The output should include '"what"'
    End

    It 'orders by severity priority (critical first)'
      result=$(db_get_insights 1)
      # First insight should be critical, last should be low
      first_severity=$(echo "$result" | grep -o '"severity":"[^"]*"' | head -1)
      The value "$first_severity" should include "critical"
    End

    It 'returns empty array for non-existent review'
      When call db_get_insights 999
      The output should eq "[]"
    End

    It 'respects limit parameter'
      result=$(db_get_insights 1 2)
      count=$(echo "$result" | grep -o '"id"' | wc -l | xargs)
      The value "$count" should eq "2"
    End
  End

  Describe 'db_search_insights()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      sqlite3 "$GGA_DB_PATH" "INSERT INTO reviews (project_path, project_name, git_branch, git_commit, files, files_count, diff_content, diff_hash, result, status, provider, duration_ms) VALUES ('/test', 'test-project', 'main', 'abc', 'f.ts', 1, 'diff', 'hash3', 'result', 'PASSED', 'claude', 100);"
      db_save_insight 1 "security" "SQL injection in user query" "" "auth.ts" "" "critical"
      db_save_insight 1 "bugfix" "Null reference in handler" "" "api.ts" "" "medium"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'finds insights by keyword'
      When call db_search_insights "injection"
      The status should be success
      The output should include "injection"
    End

    It 'returns empty array for no matches'
      When call db_search_insights "nonexistent_xyz_query"
      The output should eq "[]"
    End

    It 'returns empty array for empty query'
      When call db_search_insights ""
      The output should eq "[]"
    End
  End

  Describe 'extract_review_insights()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      sqlite3 "$GGA_DB_PATH" "INSERT INTO reviews (project_path, project_name, git_branch, git_commit, files, files_count, diff_content, diff_hash, result, status, provider, duration_ms) VALUES ('/test', 'test-project', 'main', 'abc', 'f.ts', 1, 'diff', 'hash4', 'result', 'PASSED', 'claude', 100);"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'extracts security insights'
      local result_text="Found security vulnerability: SQL injection in auth module"
      When call extract_review_insights 1 "$result_text" "auth.ts"
      The status should be success
      The output should not eq "0"
    End

    It 'extracts bugfix insights'
      local result_text="Bug found: null pointer error when user is undefined"
      When call extract_review_insights 1 "$result_text" "user.ts"
      The status should be success
      The output should not eq "0"
    End

    It 'extracts performance insights'
      local result_text="Performance issue: slow query detected, consider optimization"
      When call extract_review_insights 1 "$result_text" "db.ts"
      The status should be success
      The output should not eq "0"
    End

    It 'returns 0 for clean review'
      local result_text="STATUS: PASSED - All files comply with coding standards."
      When call extract_review_insights 1 "$result_text" "clean.ts"
      The output should eq "0"
    End

    It 'rejects invalid review_id'
      When call extract_review_insights 0 "some text" "file.ts"
      The status should be failure
    End
  End

  Describe 'db_get_insight_summaries()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      # Insert two reviews for different projects
      sqlite3 "$GGA_DB_PATH" "INSERT INTO reviews (project_path, project_name, git_branch, git_commit, files, files_count, diff_content, diff_hash, result, status, provider, duration_ms) VALUES ('/test', 'project-alpha', 'main', 'aaa', 'f.ts', 1, 'diff', 'sumhash1', 'result', 'PASSED', 'claude', 100);"
      sqlite3 "$GGA_DB_PATH" "INSERT INTO reviews (project_path, project_name, git_branch, git_commit, files, files_count, diff_content, diff_hash, result, status, provider, duration_ms) VALUES ('/test2', 'project-beta', 'main', 'bbb', 'g.ts', 1, 'diff2', 'sumhash2', 'result2', 'FAILED', 'claude', 200);"
      # Insert insights across both projects
      db_save_insight 1 "security" "SQL injection risk" "Sanitize inputs" "auth.ts" "Use parameterized queries" "critical"
      db_save_insight 1 "bugfix" "Null pointer fix" "Missing null check" "api.ts" "Always check nulls" "medium"
      db_save_insight 2 "performance" "Slow query" "Missing index" "db.ts" "Add index" "high"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns summaries as JSON array'
      result=$(db_get_insight_summaries)
      The value "$result" should start with "["
      The value "$result" should end with "]"
    End

    It 'includes correct fields'
      result=$(db_get_insight_summaries)
      The value "$result" should include '"type"'
      The value "$result" should include '"what"'
      The value "$result" should include '"severity"'
      The value "$result" should include '"file_path"'
      The value "$result" should include '"project"'
      The value "$result" should include '"date"'
    End

    It 'filters by project name'
      result=$(db_get_insight_summaries "project-alpha")
      The value "$result" should include "project-alpha"
      The value "$result" should not include "project-beta"
    End

    It 'respects limit parameter'
      result=$(db_get_insight_summaries "" 1)
      count=$(echo "$result" | grep -o '"type"' | wc -l | xargs)
      The value "$count" should eq "1"
    End

    It 'returns empty array for empty database'
      # Use a fresh database with no insights
      local empty_dir
      empty_dir=$(mktemp -d)
      export GGA_DB_PATH="$empty_dir/empty_$$.db"
      db_init > /dev/null 2>&1
      When call db_get_insight_summaries
      The output should eq "[]"
      rm -rf "$empty_dir"
    End
  End
End
