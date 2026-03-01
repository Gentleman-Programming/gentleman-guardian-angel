# shellcheck shell=bash

Describe 'Engram Bridge'
  Include "$LIB_DIR/config.sh"
  Include "$LIB_DIR/sqlite.sh"
  Include "$LIB_DIR/engram_bridge.sh"

  no_sqlite3() {
    ! command -v sqlite3 &>/dev/null
  }

  Describe '_engram_map_type()'
    It 'maps security to observation'
      When call _engram_map_type "security"
      The output should eq "observation"
    End

    It 'maps bugfix to observation'
      When call _engram_map_type "bugfix"
      The output should eq "observation"
    End

    It 'maps decision to decision'
      When call _engram_map_type "decision"
      The output should eq "decision"
    End

    It 'maps pattern to pattern'
      When call _engram_map_type "pattern"
      The output should eq "pattern"
    End

    It 'maps style to insight'
      When call _engram_map_type "style"
      The output should eq "insight"
    End

    It 'maps performance to observation'
      When call _engram_map_type "performance"
      The output should eq "observation"
    End

    It 'maps unknown types to observation'
      When call _engram_map_type "unknown"
      The output should eq "observation"
    End
  End

  Describe '_engram_map_strength()'
    It 'maps critical to 1.0'
      When call _engram_map_strength "critical"
      The output should eq "1.0"
    End

    It 'maps high to 0.8'
      When call _engram_map_strength "high"
      The output should eq "0.8"
    End

    It 'maps medium to 0.5'
      When call _engram_map_strength "medium"
      The output should eq "0.5"
    End

    It 'maps low to 0.3'
      When call _engram_map_strength "low"
      The output should eq "0.3"
    End

    It 'defaults unknown to 0.5'
      When call _engram_map_strength "unknown"
      The output should eq "0.5"
    End
  End

  Describe 'engram_format_insight()'
    It 'returns valid JSON'
      result=$(engram_format_insight "security" "SQL injection found" "auth.ts" "high" "my-project")
      The value "$result" should include '"category"'
      The value "$result" should include '"content"'
      The value "$result" should include '"strength"'
    End

    It 'maps type to engram category'
      result=$(engram_format_insight "decision" "Use JWT auth" "" "medium" "")
      The value "$result" should include '"category":"decision"'
    End

    It 'includes metadata'
      result=$(engram_format_insight "bugfix" "Fix null ref" "api.ts" "high" "my-app")
      The value "$result" should include '"gga_type":"bugfix"'
      The value "$result" should include '"severity":"high"'
    End

    It 'fails on empty content'
      When call engram_format_insight "bugfix" "" "" "low" ""
      The status should be failure
    End
  End

  Describe 'engram_export_review()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init > /dev/null 2>&1
      sqlite3 "$GGA_DB_PATH" "INSERT INTO reviews (project_path, project_name, git_branch, git_commit, files, files_count, diff_content, diff_hash, result, status, provider, duration_ms) VALUES ('/test', 'test-project', 'main', 'abc', 'f.ts', 1, 'diff', 'ehash1', 'result', 'PASSED', 'claude', 100);"
      db_save_insight 1 "security" "SQL injection risk" "" "auth.ts" "" "high"
      db_save_insight 1 "bugfix" "Null pointer fix" "" "api.ts" "" "medium"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'exports insights as JSON'
      result=$(engram_export_review 1)
      The value "$result" should include '"category"'
      The value "$result" should include '"content"'
    End

    It 'validates review_id as integer'
      When call engram_export_review "invalid"
      The status should be failure
      The stderr should include "invalid"
    End

    It 'returns 0 for review with no insights'
      sqlite3 "$GGA_DB_PATH" "INSERT INTO reviews (project_path, project_name, git_branch, git_commit, files, files_count, diff_content, diff_hash, result, status, provider, duration_ms) VALUES ('/test', 'test2', 'main', 'def', 'g.ts', 1, 'diff2', 'ehash2', 'result2', 'PASSED', 'claude', 100);"
      When call engram_export_review 2
      The output should eq "0"
    End

    It 'writes to output directory when specified'
      local out_dir="$TEMP_DIR/engram_out"
      count=$(engram_export_review 1 "$out_dir")
      The value "$count" should eq "2"
      The path "$out_dir" should be directory
    End
  End

  Describe 'engram_export_recent()'
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

    It 'validates days as integer'
      # "abc" should fallback to default 7
      When call engram_export_recent "abc"
      The status should be success
      The output should include "No reviews"
    End

    It 'handles empty database'
      When call engram_export_recent 7
      The output should include "No reviews"
    End
  End

  Describe 'engram_check()'
    It 'reports disabled when ENGRAM_ENABLED is false'
      export GGA_ENGRAM_ENABLED="false"
      When call engram_check
      The status should be failure
      The output should include "disabled"
    End
  End

  Describe 'engram_is_available()'
    It 'returns false when disabled'
      export GGA_ENGRAM_ENABLED="false"
      When call engram_is_available
      The status should be failure
    End
  End

  Describe 'engram_save_observation()'
    It 'returns immediately when disabled'
      export GGA_ENGRAM_ENABLED="false"
      When call engram_save_observation "test" "review" "content" "project"
      The status should be success
    End

    It 'returns immediately with empty title'
      export GGA_ENGRAM_ENABLED="true"
      When call engram_save_observation "" "review" "content" "project"
      The status should be success
    End
  End

  Describe 'engram_search()'
    It 'returns immediately when disabled'
      export GGA_ENGRAM_ENABLED="false"
      When call engram_search "test query" "project"
      The status should be success
    End

    It 'returns immediately with empty query'
      export GGA_ENGRAM_ENABLED="true"
      When call engram_search "" "project"
      The status should be success
    End
  End

  Describe 'engram_get_review_context()'
    It 'returns immediately when disabled'
      export GGA_ENGRAM_ENABLED="false"
      When call engram_get_review_context "file.ts" "project"
      The status should be success
    End

    It 'returns immediately with empty files'
      export GGA_ENGRAM_ENABLED="true"
      When call engram_get_review_context "" "project"
      The status should be success
    End
  End
End
