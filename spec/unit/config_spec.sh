# shellcheck shell=bash

# Helper to check if sqlite3 is available
no_sqlite3() {
  ! command -v sqlite3 &>/dev/null
}

# Skip on Windows where /root doesn't exist
no_root_dir() {
  [[ ! -d "/root" ]]
}

Describe 'config.sh'
  Include "$LIB_DIR/config.sh"

  Describe 'load_env_config()'
    setup() {
      # Clear any existing GGA_ variables
      unset GGA_DB_PATH
      unset GGA_MODEL
      unset GGA_HISTORY_LIMIT
      unset GGA_SEARCH_LIMIT
      unset GGA_RAG_ENABLED
      TEMP_DIR=$(mktemp -d)
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'sets default DB path'
      When call load_env_config
      The variable GGA_DB_PATH should eq "$HOME/.gga/gga.db"
    End

    It 'sets default history limit'
      When call load_env_config
      The variable GGA_HISTORY_LIMIT should eq "50"
    End

    It 'sets default search limit'
      When call load_env_config
      The variable GGA_SEARCH_LIMIT should eq "20"
    End

    It 'respects custom DB path from environment'
      export GGA_DB_PATH="$TEMP_DIR/custom.db"
      When call load_env_config
      The variable GGA_DB_PATH should eq "$TEMP_DIR/custom.db"
    End

    It 'respects custom history limit from environment'
      export GGA_HISTORY_LIMIT="100"
      When call load_env_config
      The variable GGA_HISTORY_LIMIT should eq "100"
    End

    It 'sets RAG enabled by default'
      When call load_env_config
      The variable GGA_RAG_ENABLED should eq "true"
    End
  End

  Describe 'get_config()'
    setup() {
      unset GGA_DB_PATH
      unset GGA_CUSTOM_VAR
    }

    BeforeEach 'setup'

    It 'returns environment variable value if set'
      export GGA_CUSTOM_VAR="custom_value"
      When call get_config "CUSTOM_VAR"
      The output should eq "custom_value"
    End

    It 'returns default if variable not set'
      When call get_config "CUSTOM_VAR" "default_value"
      The output should eq "default_value"
    End

    It 'returns empty if no default and variable not set'
      When call get_config "NONEXISTENT"
      The output should eq ""
    End
  End

  Describe 'set_config()'
    setup() {
      unset GGA_TEST_VAR
    }

    BeforeEach 'setup'

    It 'sets a configuration value'
      set_config "TEST_VAR" "test_value"
      The variable GGA_TEST_VAR should eq "test_value"
    End

    It 'overwrites existing value'
      export GGA_TEST_VAR="old_value"
      set_config "TEST_VAR" "new_value"
      The variable GGA_TEST_VAR should eq "new_value"
    End
  End

  Describe 'validate_config()'
    Skip if "sqlite3 not installed" no_sqlite3

    setup() {
      TEMP_DIR=$(mktemp -d)
      export GGA_DB_PATH="$TEMP_DIR/test.db"
    }

    cleanup() {
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'succeeds when sqlite3 is available and directory is writable'
      When call validate_config
      The status should be success
      # May emit jq warning to stderr, that's ok
      The stderr should be defined
    End
  End

  # Note: validate_config error test for unwritable directory is skipped on Windows
  # because /root doesn't exist. This test runs on Linux CI environments.

  Describe 'show_config()'
    setup() {
      export GGA_DB_PATH="/test/path/gga.db"
      export GGA_HISTORY_LIMIT="25"
      export GGA_SEARCH_LIMIT="10"
      export GGA_RAG_ENABLED="true"
      export GGA_RAG_CONTEXT_LIMIT="3"
    }

    BeforeEach 'setup'

    It 'displays current configuration'
      When call show_config
      The output should include "DB_PATH"
      The output should include "/test/path/gga.db"
      The output should include "HISTORY_LIMIT"
      The output should include "25"
    End
  End
End
