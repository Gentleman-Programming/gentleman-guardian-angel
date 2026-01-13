# shellcheck shell=bash

Describe 'gga commands'
  # Path to the gga script
  gga() {
    "$PROJECT_ROOT/bin/gga" "$@"
  }

  Describe 'gga version'
    It 'returns version number'
      When call gga version
      The status should be success
      The output should include "gga v"
    End

    It 'accepts --version flag'
      When call gga --version
      The status should be success
      The output should include "gga v"
    End

    It 'accepts -v flag'
      When call gga -v
      The status should be success
      The output should include "gga v"
    End
  End

  Describe 'gga help'
    It 'shows help message'
      When call gga help
      The status should be success
      The output should include "USAGE"
      The output should include "COMMANDS"
    End

    It 'accepts --help flag'
      When call gga --help
      The status should be success
      The output should include "USAGE"
    End

    It 'shows help when no command given'
      When call gga
      The status should be success
      The output should include "USAGE"
    End

    It 'lists all commands'
      When call gga help
      The output should include "run"
      The output should include "install"
      The output should include "uninstall"
      The output should include "config"
      The output should include "init"
      The output should include "cache"
    End

    It 'shows --ci option in help'
      When call gga help
      The output should include "--ci"
      The output should include "CI mode"
    End
  End

  Describe 'gga init'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR"
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'creates .gga config file'
      When call gga init
      The status should be success
      The output should be present
      The path ".gga" should be file
    End

    It 'config file contains PROVIDER'
      gga init > /dev/null
      The contents of file ".gga" should include "PROVIDER"
    End

    It 'config file contains FILE_PATTERNS'
      gga init > /dev/null
      The contents of file ".gga" should include "FILE_PATTERNS"
    End

    It 'config file contains EXCLUDE_PATTERNS'
      gga init > /dev/null
      The contents of file ".gga" should include "EXCLUDE_PATTERNS"
    End

    It 'config file contains RULES_FILE'
      gga init > /dev/null
      The contents of file ".gga" should include "RULES_FILE"
    End

    It 'config file contains STRICT_MODE'
      gga init > /dev/null
      The contents of file ".gga" should include "STRICT_MODE"
    End
  End

  Describe 'gga config'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR"
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'shows configuration'
      When call gga config
      The status should be success
      The output should include "Configuration"
    End

    It 'shows provider not configured when no config'
      When call gga config
      The output should include "Not configured"
    End

    It 'shows provider when configured'
      echo 'PROVIDER="claude"' > .gga
      When call gga config
      The output should include "claude"
    End

    It 'shows rules file status'
      When call gga config
      The output should include "Rules File"
    End
  End

  Describe 'gga install'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR"
      git init --quiet
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'creates pre-commit hook'
      When call gga install
      The status should be success
      The output should be present
      The path ".git/hooks/pre-commit" should be file
    End

    It 'hook contains gga run command'
      gga install > /dev/null
      The contents of file ".git/hooks/pre-commit" should include "gga run"
    End

    It 'hook is executable'
      gga install > /dev/null
      The path ".git/hooks/pre-commit" should be executable
    End

    It 'fails if not in git repo'
      rm -rf .git
      When call gga install
      The status should be failure
      The output should include "Not a git repository"
    End
  End

  Describe 'gga uninstall'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR"
      git init --quiet
      gga install > /dev/null
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'removes pre-commit hook'
      When call gga uninstall
      The status should be success
      The output should be present
      The path ".git/hooks/pre-commit" should not be exist
    End

    It 'succeeds if hook does not exist'
      rm .git/hooks/pre-commit
      When call gga uninstall
      The status should be success
      The output should be present
    End
  End

  Describe 'gga cache'
    setup() {
      TEMP_DIR=$(mktemp -d)
      cd "$TEMP_DIR"
      git init --quiet
      echo "rules" > AGENTS.md
      echo 'PROVIDER="claude"' > .gga
    }

    cleanup() {
      cd /
      rm -rf "$TEMP_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    Describe 'gga cache status'
      It 'shows cache status'
        When call gga cache status
        The status should be success
        The output should include "Cache Status"
      End
    End

    Describe 'gga cache clear'
      It 'clears project cache'
        When call gga cache clear
        The status should be success
        The output should include "Cleared cache"
      End
    End

    Describe 'gga cache clear-all'
      It 'clears all cache'
        When call gga cache clear-all
        The status should be success
        The output should include "Cleared all cache"
      End
    End

    Describe 'invalid subcommand'
      It 'fails for unknown cache subcommand'
        When call gga cache invalid
        The status should be failure
        The output should include "Unknown cache command"
      End
    End
  End

  Describe 'unknown command'
    It 'fails with error message'
      When call gga unknown-command
      The status should be failure
      The output should include "Unknown command"
    End
  End
End
