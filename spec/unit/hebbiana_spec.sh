# shellcheck shell=bash

# Helper to check if jq is available
no_jq() {
  ! command -v jq &>/dev/null
}

Describe 'hebbiana.sh'
  Include "$LIB_DIR/hebbiana.sh"

  Skip if "jq not installed" no_jq

  Describe 'hebbian_extract_concepts()'
    It 'extracts authentication pattern'
      When call hebbian_extract_concepts "login auth token jwt session"
      The output should include "pattern:authentication"
    End

    It 'extracts security pattern'
      When call hebbian_extract_concepts "XSS injection sanitize escape"
      The output should include "pattern:security"
    End

    It 'extracts database pattern'
      When call hebbian_extract_concepts "SELECT * FROM users WHERE id = 1"
      The output should include "pattern:database"
    End

    It 'extracts api pattern'
      When call hebbian_extract_concepts "fetch api endpoint rest graphql"
      The output should include "pattern:api"
    End

    It 'extracts validation pattern'
      When call hebbian_extract_concepts "validate schema zod input"
      The output should include "pattern:validation"
    End

    It 'extracts error pattern'
      When call hebbian_extract_concepts "try catch throw exception error"
      The output should include "pattern:error"
    End

    It 'extracts file references'
      When call hebbian_extract_concepts "auth.ts login.js utils.py"
      The output should include "file:auth.ts"
      The output should include "file:login.js"
    End

    It 'detects null reference errors'
      When call hebbian_extract_concepts "null undefined check"
      The output should include "error:null_reference"
    End

    It 'returns empty for empty input'
      When call hebbian_extract_concepts ""
      The output should equal ""
    End

    It 'extracts multiple patterns'
      When call hebbian_extract_concepts "login jwt SQL injection validate"
      The output should include "pattern:authentication"
      The output should include "pattern:security"
      The output should include "pattern:database"
    End
  End

  Describe 'hebbian_init_schema()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      # Create minimal database first
      sqlite3 "$GGA_DB_PATH" "CREATE TABLE IF NOT EXISTS reviews (id INTEGER PRIMARY KEY);"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'creates concepts table'
      When call hebbian_init_schema
      The status should be success
      local result=$(sqlite3 "$GGA_DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='concepts';")
      Assert [ "$result" = "concepts" ]
    End

    It 'creates associations table'
      When call hebbian_init_schema
      The status should be success
      local result=$(sqlite3 "$GGA_DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='associations';")
      Assert [ "$result" = "associations" ]
    End
  End

  Describe 'hebbian_update_association()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      sqlite3 "$GGA_DB_PATH" "CREATE TABLE IF NOT EXISTS reviews (id INTEGER PRIMARY KEY);"
      hebbian_init_schema >/dev/null 2>&1
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'creates new association'
      When call hebbian_update_association "pattern:auth" "pattern:security" 1.0 1.0 "review"
      The status should be success
      local result=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM associations WHERE concept_a='pattern:auth' AND concept_b='pattern:security';")
      Assert [ "$result" = "1" ]
    End

    It 'ignores self-associations'
      When call hebbian_update_association "pattern:auth" "pattern:auth"
      The status should be success
      local result=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM associations;")
      Assert [ "$result" = "0" ]
    End

    It 'orders concepts alphabetically'
      When call hebbian_update_association "pattern:security" "pattern:auth"
      The status should be success
      local result=$(sqlite3 "$GGA_DB_PATH" "SELECT concept_a FROM associations LIMIT 1;")
      Assert [ "$result" = "pattern:auth" ]
    End
  End

  Describe 'hebbian_learn()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      sqlite3 "$GGA_DB_PATH" "CREATE TABLE IF NOT EXISTS reviews (id INTEGER PRIMARY KEY);"
      hebbian_init_schema >/dev/null 2>&1
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'learns pairwise associations'
      local concepts=$'pattern:auth\npattern:security\npattern:validation'
      When call hebbian_learn "$concepts" "review"
      The output should include "3 associations"
      The output should include "3 concepts"
    End

    It 'returns early for single concept'
      local concepts="pattern:auth"
      When call hebbian_learn "$concepts" "review"
      The status should be success
    End

    It 'returns early for empty input'
      When call hebbian_learn "" "review"
      The status should be success
    End
  End

  Describe 'hebbian_decay()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      sqlite3 "$GGA_DB_PATH" "CREATE TABLE IF NOT EXISTS reviews (id INTEGER PRIMARY KEY);"
      hebbian_init_schema >/dev/null 2>&1
      # Create test associations
      sqlite3 "$GGA_DB_PATH" "INSERT INTO associations (concept_a, concept_b, weight, context) VALUES ('a', 'b', 0.8, 'review');"
      sqlite3 "$GGA_DB_PATH" "INSERT INTO associations (concept_a, concept_b, weight, context) VALUES ('c', 'd', 0.05, 'review');"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'applies decay to weights'
      When call hebbian_decay 1
      The output should include "Decay applied"
      local weight=$(sqlite3 "$GGA_DB_PATH" "SELECT printf('%.2f', weight) FROM associations WHERE concept_a='a';")
      # 0.8 * 0.99 = 0.792
      Assert [ "$weight" = "0.79" ]
    End

    It 'removes associations below threshold'
      When call hebbian_decay 1
      The output should include "Removed"
      # 0.05 * 0.99 = 0.0495 < 0.1 threshold
      local count=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM associations WHERE concept_a='c';")
      Assert [ "$count" = "0" ]
    End
  End

  Describe 'hebbian_get_related()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      sqlite3 "$GGA_DB_PATH" "CREATE TABLE IF NOT EXISTS reviews (id INTEGER PRIMARY KEY);"
      hebbian_init_schema >/dev/null 2>&1
      sqlite3 "$GGA_DB_PATH" "INSERT INTO associations (concept_a, concept_b, weight, context) VALUES ('pattern:auth', 'pattern:security', 0.9, 'review');"
      sqlite3 "$GGA_DB_PATH" "INSERT INTO associations (concept_a, concept_b, weight, context) VALUES ('pattern:auth', 'pattern:validation', 0.7, 'review');"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns related concepts'
      When call hebbian_get_related "pattern:auth" 10
      The output should include "pattern:security"
      The output should include "pattern:validation"
    End

    It 'returns empty with empty concept'
      When call hebbian_get_related ""
      The status should be failure
    End

    It 'respects limit'
      When call hebbian_get_related "pattern:auth" 1
      The output should include "pattern:security"
      The lines of output should equal 1
    End
  End

  Describe 'hebbian_check()'
    It 'reports disabled when HEBBIAN_ENABLED is false'
      export HEBBIAN_ENABLED="false"
      When call hebbian_check
      The output should include "disabled"
      The status should be failure
    End

    It 'reports missing database'
      export HEBBIAN_ENABLED="true"
      export GGA_DB_PATH="/nonexistent/path/db.db"
      When call hebbian_check
      The output should include "not found"
      The status should be failure
    End
  End

  Describe 'hebbian_stats()'
    It 'reports no database if missing'
      export GGA_DB_PATH="/nonexistent/path/db.db"
      When call hebbian_stats
      The output should include "No database"
      The status should be failure
    End

    Describe 'with test database'
      setup() {
        TEMP_DIR=$(mktemp -d)
        export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
        sqlite3 "$GGA_DB_PATH" "CREATE TABLE IF NOT EXISTS reviews (id INTEGER PRIMARY KEY);"
        hebbian_init_schema >/dev/null 2>&1
        sqlite3 "$GGA_DB_PATH" "INSERT INTO concepts (id, type) VALUES ('pattern:auth', 'pattern'), ('pattern:security', 'pattern');"
        sqlite3 "$GGA_DB_PATH" "INSERT INTO associations (concept_a, concept_b, weight, context) VALUES ('pattern:auth', 'pattern:security', 0.8, 'review');"
      }

      cleanup() {
        rm -rf "$TEMP_DIR"
      }

      BeforeEach 'setup'
      AfterEach 'cleanup'

      It 'shows correct statistics'
        When call hebbian_stats
        The output should include "Concepts: 2"
        The output should include "Associations: 1"
      End
    End
  End

  Describe 'hebbian_predict()'
    It 'fails with empty input'
      When call hebbian_predict ""
      The status should be failure
      The stderr should include "Usage:"
    End

    It 'fails without database'
      export GGA_DB_PATH="/nonexistent/path/db.db"
      When call hebbian_predict "test text"
      The status should be failure
      The stderr should include "No database"
    End

    Describe 'with test database'
      setup() {
        TEMP_DIR=$(mktemp -d)
        export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
        sqlite3 "$GGA_DB_PATH" "CREATE TABLE IF NOT EXISTS reviews (id INTEGER PRIMARY KEY);"
        hebbian_init_schema >/dev/null 2>&1
        # Add some associations
        sqlite3 "$GGA_DB_PATH" "INSERT INTO associations (concept_a, concept_b, weight, context) VALUES
          ('pattern:authentication', 'pattern:security', 0.9, 'review'),
          ('pattern:authentication', 'pattern:validation', 0.7, 'review'),
          ('pattern:security', 'pattern:validation', 0.6, 'review');"
      }

      cleanup() {
        rm -rf "$TEMP_DIR"
      }

      BeforeEach 'setup'
      AfterEach 'cleanup'

      It 'detects concepts from text input'
        When call hebbian_predict "login auth token"
        The output should include "Detected concepts"
        The output should include "pattern:authentication"
      End

      It 'shows related concepts'
        When call hebbian_predict "login jwt authentication"
        The output should include "Related concepts"
      End
    End
  End

  Describe 'hebbian_spread_activation()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      sqlite3 "$GGA_DB_PATH" "CREATE TABLE IF NOT EXISTS reviews (id INTEGER PRIMARY KEY);"
      hebbian_init_schema >/dev/null 2>&1
      # Create test network
      sqlite3 "$GGA_DB_PATH" "INSERT INTO associations (concept_a, concept_b, weight, context) VALUES
        ('pattern:auth', 'pattern:security', 0.9, 'review'),
        ('pattern:security', 'pattern:validation', 0.8, 'review'),
        ('pattern:auth', 'file:login.ts', 0.7, 'review');"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'spreads activation to neighbors'
      local initial=$'pattern:auth'
      When call hebbian_spread_activation "$initial" 1 0.5
      The output should include "pattern:security"
      The output should include "file:login.ts"
    End

    It 'returns failure with empty input'
      When call hebbian_spread_activation ""
      The status should be failure
    End

    It 'returns failure without database'
      export GGA_DB_PATH="/nonexistent/path/db.db"
      When call hebbian_spread_activation "pattern:auth"
      The status should be failure
    End

    It 'accumulates activation over multiple iterations'
      local initial=$'pattern:auth'
      When call hebbian_spread_activation "$initial" 2 0.5
      The status should be success
      # Should reach pattern:validation through pattern:security
      The output should include "pattern:validation"
    End

    It 'outputs activation scores with concepts'
      local initial=$'pattern:auth'
      When call hebbian_spread_activation "$initial" 1 0.5
      # Output format should be "score|concept"
      The output should match pattern "*|*"
    End
  End

  Describe 'hebbian_show()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      sqlite3 "$GGA_DB_PATH" "CREATE TABLE IF NOT EXISTS reviews (id INTEGER PRIMARY KEY);"
      hebbian_init_schema >/dev/null 2>&1
      sqlite3 "$GGA_DB_PATH" "INSERT INTO associations (concept_a, concept_b, weight, context) VALUES
        ('pattern:auth', 'pattern:security', 0.9, 'review'),
        ('pattern:auth', 'pattern:validation', 0.7, 'review'),
        ('pattern:database', 'pattern:security', 0.6, 'review');"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'shows associations for specific concept'
      When call hebbian_show "pattern:auth"
      The output should include "Associations for: pattern:auth"
      The output should include "pattern:security"
      The output should include "pattern:validation"
    End

    It 'shows all associations when no concept specified'
      When call hebbian_show
      The output should include "All associations"
      The output should include "pattern:auth"
      The output should include "pattern:database"
    End

    It 'returns failure without database'
      export GGA_DB_PATH="/nonexistent/path/db.db"
      When call hebbian_show
      The status should be failure
      The output should include "No database"
    End

    It 'shows weights in output'
      When call hebbian_show "pattern:auth"
      # Should show weight values
      The output should match pattern "*0.*"
    End
  End

  Describe 'hebbian_learn_from_review()'
    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      export HEBBIAN_ENABLED="true"
      sqlite3 "$GGA_DB_PATH" "CREATE TABLE IF NOT EXISTS reviews (id INTEGER PRIMARY KEY);"
      hebbian_init_schema >/dev/null 2>&1
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'learns from review data'
      When call hebbian_learn_from_review "auth.ts" "login jwt token" "Security issue found" "FAILED"
      The status should be success
      local count=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM associations;")
      Assert [ "$count" -gt 0 ]
    End

    It 'does nothing when disabled'
      export HEBBIAN_ENABLED="false"
      When call hebbian_learn_from_review "auth.ts" "login jwt" "result" "PASSED"
      The status should be success
    End

    It 'adds status as a concept'
      When call hebbian_learn_from_review "auth.ts" "login" "result" "FAILED"
      The status should be success
      local has_status=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM concepts WHERE id='status:FAILED';")
      Assert [ "$has_status" -gt 0 ]
    End

    It 'creates associations between files and patterns'
      When call hebbian_learn_from_review "auth.ts" "login jwt token validation" "Security passed" "PASSED"
      The status should be success
      # Should have associations between file:auth.ts and patterns
      local count=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM associations WHERE concept_a LIKE 'file:%' OR concept_b LIKE 'file:%';")
      Assert [ "$count" -gt 0 ]
    End
  End
End
