# shellcheck shell=bash

Describe 'session cohesion'
  Include "$LIB_DIR/hebbiana.sh"

  no_sqlite3() {
    ! command -v sqlite3 &>/dev/null
  }

  # Helper: sqlite3 with Windows \r stripping for exact comparisons
  sqlite3_clean() {
    sqlite3 "$GGA_DB_PATH" "$1" | tr -d '\r'
  }

  # Helper: run full session workflow and return association count
  run_session_workflow() {
    hebbian_start_session "abc123" "proj" "commit" >/dev/null
    _session_add_concepts "pattern:security
pattern:authentication
file:auth.ts"
    hebbian_end_session >/dev/null
    sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM associations WHERE context='session';" | tr -d '\r'
  }

  # Helper: run session with exactly 3 concepts and count pairs
  run_session_3concepts() {
    hebbian_start_session "xyz789" "proj" "commit" >/dev/null
    _session_add_concepts "pattern:security
pattern:database
file:query.ts"
    hebbian_end_session >/dev/null
    sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM associations WHERE context='session';" | tr -d '\r'
  }

  # Helper: run learn_from_review within a session
  run_session_with_review() {
    hebbian_start_session "abc123" "proj" "commit" >/dev/null
    hebbian_learn_from_review "auth.ts" "login jwt token" "Security issue found" "FAILED"
    hebbian_end_session >/dev/null
    sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM session_concepts WHERE session_id=1;" | tr -d '\r'
  }

  # Helper: check both review and session associations exist
  check_both_contexts() {
    hebbian_start_session "def456" "proj" "commit" >/dev/null
    hebbian_learn_from_review "auth.ts db.py" "login sql query" "Issue found" "FAILED"
    hebbian_end_session >/dev/null
    local review_count session_count
    review_count=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM associations WHERE context='review';" | tr -d '\r')
    session_count=$(sqlite3 "$GGA_DB_PATH" "SELECT COUNT(*) FROM associations WHERE context='session';" | tr -d '\r')
    echo "review:$review_count session:$session_count"
  }

  Describe 'schema'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      sqlite3 "$GGA_DB_PATH" "SELECT 1;" >/dev/null
      hebbian_init_schema
    }

    cleanup() {
      _HEBBIAN_SESSION_ID=""
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'creates learning_sessions table'
      When call sqlite3 "$GGA_DB_PATH" ".tables"
      The output should include "learning_sessions"
    End

    It 'creates session_concepts table'
      When call sqlite3 "$GGA_DB_PATH" ".tables"
      The output should include "session_concepts"
    End
  End

  Describe 'hebbian_start_session()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      export HEBBIAN_ENABLED="true"
      sqlite3 "$GGA_DB_PATH" "SELECT 1;" >/dev/null
      hebbian_init_schema
    }

    cleanup() {
      _HEBBIAN_SESSION_ID=""
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'creates a session and returns ID'
      When call hebbian_start_session "abc123" "my-project" "commit"
      The status should be success
      The output should not eq ""
    End

    It 'stores session in database'
      hebbian_start_session "def456" "test-proj" "commit" >/dev/null
      When call sqlite3_clean "SELECT session_ref FROM learning_sessions WHERE session_ref='def456';"
      The output should eq "def456"
    End

    It 'stores project name'
      hebbian_start_session "ghi789" "my-app" "commit" >/dev/null
      When call sqlite3_clean "SELECT project FROM learning_sessions WHERE session_ref='ghi789';"
      The output should eq "my-app"
    End

    It 'returns empty when disabled'
      export HEBBIAN_ENABLED="false"
      When call hebbian_start_session "abc123" "proj"
      The status should be success
    End

    It 'fails for empty session ref'
      When call hebbian_start_session ""
      The status should be failure
    End
  End

  Describe 'hebbian_end_session()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      export HEBBIAN_ENABLED="true"
      export HEBBIAN_LEARNING_RATE="0.1"
      export HEBBIAN_SESSION_BOOST="1.5"
      sqlite3 "$GGA_DB_PATH" "SELECT 1;" >/dev/null
      hebbian_init_schema
    }

    cleanup() {
      _HEBBIAN_SESSION_ID=""
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'returns nothing with no active session'
      _HEBBIAN_SESSION_ID=""
      When call hebbian_end_session
      The status should be success
    End

    It 'learns cross-concept associations with session context'
      When call run_session_workflow
      The output should not eq "0"
    End

    It 'creates pairwise associations for session concepts'
      When call run_session_3concepts
      The output should eq "3"
    End
  End

  Describe 'session integration with learn_from_review'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      export HEBBIAN_ENABLED="true"
      export HEBBIAN_LEARNING_RATE="0.1"
      export HEBBIAN_SESSION_BOOST="1.5"
      sqlite3 "$GGA_DB_PATH" "SELECT 1;" >/dev/null
      hebbian_init_schema
    }

    cleanup() {
      _HEBBIAN_SESSION_ID=""
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'adds concepts to active session during learn_from_review'
      When call run_session_with_review
      The output should not eq "0"
    End

    It 'creates both review and session associations'
      When call check_both_contexts
      The output should include "review:"
      The output should include "session:"
      The output should not include "review:0"
      The output should not include "session:0"
    End
  End

  Describe 'hebbian_session_stats()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test_$$.db"
      export HEBBIAN_ENABLED="true"
      sqlite3 "$GGA_DB_PATH" "SELECT 1;" >/dev/null
      hebbian_init_schema
      hebbian_start_session "abc123" "proj-a" "commit" >/dev/null
      _session_add_concepts "pattern:security
file:auth.ts"
      hebbian_end_session >/dev/null
    }

    cleanup() {
      _HEBBIAN_SESSION_ID=""
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'shows session history'
      When call hebbian_session_stats
      The output should include "Session History"
      The output should include "abc123"
    End

    It 'shows concept count'
      When call hebbian_session_stats
      The output should include "2 concepts"
    End

    It 'shows project name'
      When call hebbian_session_stats
      The output should include "proj-a"
    End
  End
End
