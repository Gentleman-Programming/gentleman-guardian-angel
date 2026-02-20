# shellcheck shell=bash

# Helper to check if jq is available
no_jq() {
  ! command -v jq &>/dev/null
}

# Helper to check if bc is available
no_bc() {
  ! command -v bc &>/dev/null
}

Describe 'semantic.sh'
  Include "$LIB_DIR/semantic.sh"

  Skip if "jq not installed" no_jq

  Describe 'cosine_similarity()'
    It 'returns 1 for identical vectors'
      local vec='[1,0,0]'
      When call cosine_similarity "$vec" "$vec"
      The output should equal '1.000000'
    End

    It 'returns 0 for orthogonal vectors'
      When call cosine_similarity '[1,0,0]' '[0,1,0]'
      The output should equal '0.000000'
    End

    It 'returns correct similarity for known vectors'
      # [1,2,3] dot [4,5,6] = 32
      # |[1,2,3]| = sqrt(14), |[4,5,6]| = sqrt(77)
      # cos = 32 / sqrt(14*77) = 32 / sqrt(1078) ≈ 0.9746
      When call cosine_similarity '[1,2,3]' '[4,5,6]'
      The output should match pattern '0.97*'
    End

    It 'returns 0 for empty first vector'
      When call cosine_similarity "" '[1,2,3]'
      The output should equal '0'
      The status should be failure
    End

    It 'returns 0 for empty second vector'
      When call cosine_similarity '[1,2,3]' ""
      The output should equal '0'
      The status should be failure
    End

    It 'returns 0 for null vectors'
      When call cosine_similarity "null" '[1,2,3]'
      The output should equal '0'
      The status should be failure
    End
  End

  Describe 'search_lexical()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      source "$LIB_DIR/config.sh"
      source "$LIB_DIR/sqlite.sh"
      load_env_config
      db_init > /dev/null 2>&1
      # Insert test data
      db_save_review "/path" "test-project" "main" "abc" \
        "auth.ts,login.ts" 2 "authentication code" "hash1" \
        "Found SQL injection" "FAILED" "claude" "" 1000
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns empty with empty query'
      When call search_lexical ""
      The status should be failure
    End

    It 'finds reviews matching query'
      When call search_lexical "auth"
      The output should include "test-project"
    End

    It 'finds reviews by result content'
      When call search_lexical "SQL injection"
      The output should include "test-project"
    End

    It 'returns empty for no matches'
      When call search_lexical "xyznonexistent123"
      The output should equal ""
    End
  End

  Describe 'search_semantic()'
    It 'returns empty with empty query'
      When call search_semantic ""
      The status should be failure
    End

    It 'fails gracefully without embedding provider'
      export GGA_EMBED_PROVIDER="none"
      When call search_semantic "test query"
      The status should be failure
    End
  End

  Describe 'search_hybrid()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      source "$LIB_DIR/config.sh"
      source "$LIB_DIR/sqlite.sh"
      load_env_config
      db_init > /dev/null 2>&1
      db_save_review "/path" "hybrid-project" "main" "abc" \
        "api.ts" 1 "api endpoint code" "hash2" \
        "API validation passed" "PASSED" "claude" "" 1000
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns empty with empty query'
      When call search_hybrid ""
      The status should be failure
    End

    It 'finds reviews via lexical component'
      When call search_hybrid "api" "1.0" "10"
      The output should include "hybrid-project"
    End

    It 'respects alpha parameter for pure lexical'
      When call search_hybrid "api" "1.0" "10"
      The output should include "hybrid-project"
    End
  End

  Describe 'find_similar()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      sqlite3 "$GGA_DB_PATH" "CREATE TABLE reviews (id INTEGER PRIMARY KEY, status TEXT, project_name TEXT, embedding TEXT);"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns empty with empty review_id'
      When call find_similar ""
      The status should be failure
    End

    It 'reports error for review without embedding'
      sqlite3 "$GGA_DB_PATH" "INSERT INTO reviews (id, status, project_name) VALUES (1, 'PASSED', 'test');"
      When call find_similar 1
      The stderr should include "no embedding"
      The status should be failure
    End
  End
End
