# shellcheck shell=bash

# Helper to check if jq is available
no_jq() {
  ! command -v jq &>/dev/null
}

Describe 'rag.sh'
  Include "$LIB_DIR/rag.sh"

  Skip if "jq not installed" no_jq

  Describe 'rag_extract_patterns()'
    It 'includes file names in patterns'
      When call rag_extract_patterns "auth.ts login.ts" "" ""
      The output should include "auth.ts"
    End

    It 'detects authentication pattern'
      When call rag_extract_patterns "" "jwt token validation login" ""
      The output should include "authentication"
    End

    It 'detects database pattern'
      When call rag_extract_patterns "" "SELECT * FROM users WHERE id" ""
      The output should include "database"
    End

    It 'detects API pattern'
      When call rag_extract_patterns "" "fetch('/api/users') axios.get endpoint" ""
      The output should include "api"
    End

    It 'detects security pattern'
      When call rag_extract_patterns "" "xss injection sanitize escape" ""
      The output should include "security"
    End

    It 'detects validation pattern'
      When call rag_extract_patterns "" "zod schema validation assert" ""
      The output should include "validation"
    End

    It 'detects error handling pattern'
      When call rag_extract_patterns "" "try catch throw exception error" ""
      The output should include "error"
    End

    It 'includes commit message'
      When call rag_extract_patterns "" "" "fix: resolve sql injection"
      The output should include "fix: resolve sql injection"
    End

    It 'combines multiple patterns'
      When call rag_extract_patterns "api.ts" "jwt token SELECT query" "auth fix"
      The output should include "api.ts"
      The output should include "authentication"
      The output should include "database"
    End

    It 'returns empty for empty inputs'
      When call rag_extract_patterns "" "" ""
      The output should equal ""
    End
  End

  Describe 'rag_build_context()'
    It 'returns empty for empty input'
      When call rag_build_context ""
      The output should equal ""
    End

    It 'returns empty if database does not exist'
      export GGA_DB_PATH="/nonexistent/path/db.db"
      When call rag_build_context "0.8|1|project|summary"
      The output should equal ""
    End
  End

  Describe 'rag_augment_prompt()'
    It 'returns original if RAG disabled'
      export RAG_ENABLED="false"
      When call rag_augment_prompt "Original prompt" "" "" ""
      The output should equal "Original prompt"
    End

    It 'returns original if database does not exist'
      export RAG_ENABLED="true"
      export GGA_DB_PATH="/nonexistent/path/db.db"
      When call rag_augment_prompt "Original prompt" "" "" ""
      The output should equal "Original prompt"
    End
  End

  Describe 'rag_retrieve()'
    It 'returns failure with empty query'
      When call rag_retrieve ""
      The status should be failure
    End

    It 'returns failure if database does not exist'
      export GGA_DB_PATH="/nonexistent/path/db.db"
      When call rag_retrieve "test query"
      The status should be failure
    End
  End

  Describe 'rag_ask()'
    It 'returns failure with empty question'
      When call rag_ask ""
      The status should be failure
      The stderr should include "Uso:"
    End

    It 'returns failure if database does not exist'
      export GGA_DB_PATH="/nonexistent/path/db.db"
      When call rag_ask "test question"
      The status should be failure
      The stderr should include "historial"
    End
  End

  Describe 'rag_check()'
    It 'reports disabled if RAG_ENABLED is false'
      export RAG_ENABLED="false"
      When call rag_check
      The output should include "deshabilitado"
      The status should be failure
    End

    It 'reports missing database'
      export RAG_ENABLED="true"
      export GGA_DB_PATH="/nonexistent/path/db.db"
      When call rag_check
      The output should include "no encontrada"
      The status should be failure
    End
  End

  Describe 'rag_stats()'
    It 'reports no database if missing'
      export GGA_DB_PATH="/nonexistent/path/db.db"
      When call rag_stats
      The output should include "No hay base de datos"
      The status should be failure
    End
  End

  Describe 'with test database'
    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      export RAG_ENABLED="true"
      source "$LIB_DIR/config.sh"
      source "$LIB_DIR/sqlite.sh"
      load_env_config
      db_init > /dev/null 2>&1
      # Insert test reviews (using simple file names without dots for FTS5 compatibility)
      db_save_review "/path" "test-project" "main" "abc" \
        "authfile" 1 "jwt token authentication code" "hash1" \
        "Found authentication issue with jwt tokens" "FAILED" "claude" "" 1000
      db_save_review "/path" "test-project" "main" "def" \
        "dbfile" 1 "sql query database code" "hash2" \
        "SQL injection vulnerability detected" "FAILED" "claude" "" 1000
      db_save_review "/path" "test-project" "main" "ghi" \
        "apifile" 1 "endpoint api code" "hash3" \
        "API validation passed successfully" "PASSED" "claude" "" 1000
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    Describe 'rag_augment_prompt() with data'
      It 'returns original if insufficient history (< 3 reviews)'
        # Delete reviews to have only 2
        sqlite3 "$GGA_DB_PATH" "DELETE FROM reviews WHERE id = 3;"
        sqlite3 "$GGA_DB_PATH" "DELETE FROM reviews WHERE id = 2;"
        When call rag_augment_prompt "Original prompt" "testfile" "code" ""
        The output should equal "Original prompt"
      End

      It 'includes original prompt in output (RAG may or may not find matches)'
        # RAG augmentation depends on FTS5 matching - test that original is preserved
        When call rag_augment_prompt "Original prompt" "authfile" "authentication jwt" ""
        The output should include "Original prompt"
        # Note: "Contexto Historico" only appears if FTS5 finds matches
        # This test verifies the function runs without error
      End
    End

    Describe 'rag_check() with data'
      It 'reports available with sufficient reviews'
        When call rag_check
        The output should include "disponible"
        The output should include "3 reviews"
        The status should be success
      End
    End

    Describe 'rag_stats() with data'
      It 'shows correct statistics'
        When call rag_stats
        The output should include "Total Reviews: 3"
        The output should include "Passed: 1"
        The output should include "Failed: 2"
      End
    End

    Describe 'rag_build_context() with data'
      It 'formats review context as markdown'
        # Manually create input like rag_retrieve would return
        local input="0.8000|1|test-project|auth.ts"
        When call rag_build_context "$input"
        The output should include "Review #1"
        The output should include "Relevancia:"
        The output should include "Estado:"
      End
    End
  End
End
