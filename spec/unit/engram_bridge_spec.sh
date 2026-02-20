# shellcheck shell=bash

Describe 'engram bridge'
  Include "$LIB_DIR/config.sh"
  Include "$LIB_DIR/sqlite.sh"
  Include "$LIB_DIR/engram_bridge.sh"

  no_sqlite3() {
    ! command -v sqlite3 &>/dev/null
  }

  Describe 'type mapping'
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

    It 'defaults unknown to observation'
      When call _engram_map_type "unknown_thing"
      The output should eq "observation"
    End
  End

  Describe 'strength mapping'
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
  End

  Describe 'engram_format_insight()'
    It 'formats insight as JSON'
      When call engram_format_insight "security" "SQL injection found" "auth.ts" "critical" "my-project"
      The output should include '"category":"observation"'
      The output should include '"content":"SQL injection found"'
      The output should include '"strength":1.0'
      The output should include '"source":"gga"'
    End

    It 'includes file in metadata'
      When call engram_format_insight "bugfix" "Null check" "handler.ts" "high"
      The output should include '"file":"handler.ts"'
    End

    It 'includes project in metadata'
      When call engram_format_insight "pattern" "Auth pattern" "" "medium" "my-app"
      The output should include '"project":"my-app"'
    End

    It 'fails for empty content'
      When call engram_format_insight "security" "" "" ""
      The status should be failure
    End

    It 'includes timestamp'
      When call engram_format_insight "style" "Formatting" "" "low"
      The output should include '"timestamp":'
    End
  End

  Describe 'engram_export_review()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init >/dev/null
      db_save_review "/tmp/proj" "test-proj" "main" "abc123" \
        "auth.ts" 1 "diff" "hash1" \
        "STATUS: FAILED" "FAILED" "mock" "" 100 2>/dev/null
      db_save_insight 1 "security" "SQL injection" "Bad input" "auth.ts" "Fix it" "critical" 2>/dev/null
      db_save_insight 1 "style" "Formatting issue" "" "auth.ts" "" "low" 2>/dev/null
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'exports insights as JSON array'
      When call engram_export_review 1
      The output should include '"category"'
      The output should include '"SQL injection"'
      The output should include '"Formatting issue"'
    End

    It 'exports to directory when specified'
      When call engram_export_review 1 "$TEMP_DIR/export"
      The output should eq "2"
    End

    It 'creates JSON file in output directory'
      # Use a helper that exports and then checks the file
      check_export_file() {
        engram_export_review 1 "$TEMP_DIR/export" >/dev/null
        ls "$TEMP_DIR/export/" 2>/dev/null
      }
      When call check_export_file
      The output should include "gga_review_1"
      The output should include ".json"
    End

    It 'returns 0 for review with no insights'
      db_save_review "/tmp/proj" "test-proj" "main" "def456" \
        "utils.py" 1 "diff2" "hash2" "STATUS: PASSED" "PASSED" "mock" "" 50 2>/dev/null
      When call engram_export_review 2
      The output should eq "0"
    End

    It 'fails for missing review_id'
      When call engram_export_review ""
      The status should be failure
    End
  End

  Describe 'engram_check()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      load_env_config
      db_init >/dev/null
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'reports disabled when not enabled'
      export ENGRAM_ENABLED="false"
      When call engram_check
      The output should include "disabled"
      The status should be failure
    End

    It 'reports ready when enabled with insights'
      export ENGRAM_ENABLED="true"
      db_save_review "/tmp/proj" "test-proj" "main" "abc123" \
        "auth.ts" 1 "diff" "hash1" "STATUS: FAILED" "FAILED" "mock" "" 100 2>/dev/null
      db_save_insight 1 "security" "SQL injection" "" "auth.ts" "" "critical" 2>/dev/null
      When call engram_check
      The output should include "ready"
      The output should include "1 insights"
      The status should be success
    End
  End
End
