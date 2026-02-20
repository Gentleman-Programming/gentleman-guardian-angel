# shellcheck shell=bash

Describe 'progressive disclosure (rag_build_context)'
  Include "$LIB_DIR/config.sh"
  Include "$LIB_DIR/sqlite.sh"
  Include "$LIB_DIR/rag.sh"

  no_sqlite3() {
    ! command -v sqlite3 &>/dev/null
  }

  Describe 'disclosure levels'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      export RAG_DISCLOSURE_HIGH="0.7"
      export RAG_DISCLOSURE_MED="0.5"
      export RAG_MAX_TOKENS="5000"
      load_env_config
      db_init >/dev/null

      # Create review with insights
      db_save_review "/tmp/proj" "test-proj" "main" "abc123" \
        "auth.ts" 1 "diff content" "hash1" \
        "STATUS: FAILED\nSQL injection vulnerability" "FAILED" "mock" "" 100 2>/dev/null
      db_save_insight 1 "security" "SQL injection in query" "Bad input" \
        "auth.ts:42" "Use params" "critical" 2>/dev/null

      # Create review without insights (legacy)
      db_save_review "/tmp/proj" "test-proj" "main" "def456" \
        "utils.py" 1 "diff2" "hash2" \
        "STATUS: PASSED\nLooks good" "PASSED" "mock" "" 50 2>/dev/null
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'uses compact format for low-relevance results'
      # Score 0.3 is below medium threshold (0.5)
      When call rag_build_context "0.3000|1|test-proj|auth.ts"
      The output should include "30%"
      The output should not include "### Review"
      The output should include "security"
    End

    It 'uses detail format for medium-relevance results'
      # Score 0.6 is between medium (0.5) and high (0.7)
      When call rag_build_context "0.6000|1|test-proj|auth.ts"
      The output should include "### Review #1"
      The output should include "60%"
      The output should include "security"
      The output should not include "DETAILED"
    End

    It 'uses full format for high-relevance results'
      # Score 0.8 is above high threshold (0.7)
      When call rag_build_context "0.8000|1|test-proj|auth.ts"
      The output should include "### Review #1"
      The output should include "DETAILED"
      The output should include "80%"
    End

    It 'includes raw findings in full disclosure'
      When call rag_build_context "0.8000|1|test-proj|auth.ts"
      The output should include "Status:"
      The output should include "FAILED"
    End

    It 'handles legacy reviews without insights in compact mode'
      When call rag_build_context "0.3000|2|test-proj|utils.py"
      The output should include "PASSED"
    End

    It 'handles legacy reviews without insights in detail mode'
      When call rag_build_context "0.6000|2|test-proj|utils.py"
      The output should include "PASSED"
    End

    It 'handles legacy reviews in full mode'
      When call rag_build_context "0.8000|2|test-proj|utils.py"
      The output should include "DETAILED"
      The output should include "PASSED"
    End

    It 'mixes disclosure levels for multiple results'
      local input="0.8000|1|test-proj|auth.ts
0.3000|2|test-proj|utils.py"
      When call rag_build_context "$input"
      The output should include "DETAILED"
      The output should include "#1"
      The output should include "#2"
    End

    It 'returns empty for empty input'
      When call rag_build_context ""
      The status should be success
    End
  End

  Describe 'token budget respects disclosure'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      export RAG_DISCLOSURE_HIGH="0.7"
      export RAG_DISCLOSURE_MED="0.5"
      export RAG_MAX_TOKENS="100"
      load_env_config
      db_init >/dev/null

      db_save_review "/tmp/proj" "test-proj" "main" "abc123" \
        "auth.ts" 1 "diff" "hash1" \
        "STATUS: FAILED\nSome issue" "FAILED" "mock" "" 100 2>/dev/null
      db_save_insight 1 "security" "SQL injection" "" "auth.ts" "" "critical" 2>/dev/null
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'fits more compact entries in limited token budget'
      # Compact entries use ~15 tokens each, so we can fit more
      When call rag_build_context "0.3000|1|test-proj|auth.ts"
      The status should be success
      The output should include "#1"
    End
  End

  Describe 'configurable thresholds'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      export RAG_MAX_TOKENS="5000"
      load_env_config
      db_init >/dev/null

      db_save_review "/tmp/proj" "test-proj" "main" "abc123" \
        "auth.ts" 1 "diff" "hash1" \
        "STATUS: FAILED\nIssue" "FAILED" "mock" "" 100 2>/dev/null
      db_save_insight 1 "security" "SQL injection" "" "auth.ts" "" "critical" 2>/dev/null
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'respects custom high threshold'
      export RAG_DISCLOSURE_HIGH="0.9"
      export RAG_DISCLOSURE_MED="0.5"
      # 0.8 is now below the high threshold, should be detail not full
      When call rag_build_context "0.8000|1|test-proj|auth.ts"
      The output should not include "DETAILED"
      The output should include "### Review #1"
    End

    It 'respects custom medium threshold'
      export RAG_DISCLOSURE_HIGH="0.9"
      export RAG_DISCLOSURE_MED="0.8"
      # 0.75 is below medium (0.8), should be compact
      When call rag_build_context "0.7500|1|test-proj|auth.ts"
      The output should not include "### Review"
    End
  End
End
