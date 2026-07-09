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

    It 'renders configuration paths without literal ANSI escapes'
      When call gga help
      The output should include ".gga"
      The output should not include "\\033"
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
      TEST_HOME=$(mktemp -d)
      ORIGINAL_HOME="${HOME:-}"
      ORIGINAL_XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-}"
      ORIGINAL_APPDATA="${APPDATA:-}"
      ORIGINAL_PATH="$PATH"
      TEST_BIN_DIR=$(mktemp -d)
      ORIGINAL_GGA_OPENCODE_VARIANT="${GGA_OPENCODE_VARIANT:-}"
      ORIGINAL_GGA_OPENCODE_AGENT="${GGA_OPENCODE_AGENT:-}"
      HOME="$TEST_HOME"
      PATH="$TEST_BIN_DIR:$PATH"
      XDG_CONFIG_HOME="$TEST_HOME/.config"
      unset APPDATA
      unset GGA_OPENCODE_VARIANT
      unset GGA_OPENCODE_AGENT
      cd "$TEMP_DIR"
    }

    cleanup() {
      cd /
      HOME="$ORIGINAL_HOME"
      if [[ -n "$ORIGINAL_XDG_CONFIG_HOME" ]]; then
        XDG_CONFIG_HOME="$ORIGINAL_XDG_CONFIG_HOME"
      else
        unset XDG_CONFIG_HOME
      fi
      if [[ -n "$ORIGINAL_APPDATA" ]]; then
        APPDATA="$ORIGINAL_APPDATA"
      else
        unset APPDATA
      fi
      PATH="$ORIGINAL_PATH"
      if [[ -n "$ORIGINAL_GGA_OPENCODE_VARIANT" ]]; then
        GGA_OPENCODE_VARIANT="$ORIGINAL_GGA_OPENCODE_VARIANT"
      else
        unset GGA_OPENCODE_VARIANT
      fi
      if [[ -n "$ORIGINAL_GGA_OPENCODE_AGENT" ]]; then
        GGA_OPENCODE_AGENT="$ORIGINAL_GGA_OPENCODE_AGENT"
      else
        unset GGA_OPENCODE_AGENT
      fi
      rm -rf "$TEMP_DIR" "$TEST_HOME" "$TEST_BIN_DIR"
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

    Describe 'CRLF provider parsing'
      Parameters
        "lmstudio"
        "lmstudio:qwen/qwen3.5-9b"
        "minimax:MiniMax-M3"
      End

      It 'preserves provider variable name and value while stripping CRLF characters'
        printf 'PROVIDER="%s"\r\nFILE_PATTERNS="*.sh"\r\n' "$1" > .gga
        When call gga config
        The status should be success
        The output should include "PROVIDER:"
        The output should include "$1"
        The output should include "*.sh"
      End
    End

    It 'loads project config with CRLF line endings'
      printf 'PROVIDER="claude"\r\nFILE_PATTERNS="*.sh"\r\n' > .gga
      When call gga config
      The status should be success
      The output should include "claude"
      The output should include "*.sh"
    End

    It 'loads project config with UTF-8 BOM'
      printf '\357\273\277PROVIDER="claude"\n' > .gga
      When call gga config
      The status should be success
      The output should include "claude"
    End

    It 'loads global config from Windows-style APPDATA path in Git Bash'
      mkdir -p "$TEST_BIN_DIR" "$TEST_HOME/AppData/Roaming/gga"
      cat > "$TEST_BIN_DIR/cygpath" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-u" ]]; then
  echo "$TEST_HOME/AppData/Roaming"
fi
EOF
      chmod +x "$TEST_BIN_DIR/cygpath"
      printf 'PROVIDER="claude"\r\n' > "$TEST_HOME/AppData/Roaming/gga/config"

      When call env APPDATA='C:\Users\Test\AppData\Roaming' TEST_HOME="$TEST_HOME" PATH="$PATH" "$PROJECT_ROOT/bin/gga" config
      The status should be success
      The output should include "claude"
    End

    It 'shows OpenCode variant and agent when configured'
      cat > .gga <<'EOF'
PROVIDER="opencode"
OPENCODE_VARIANT="high"
OPENCODE_AGENT="gga-reviewer"
EOF
      When call gga config
      The output should include "OPENCODE_VARIANT"
      The output should include "high"
      The output should include "OPENCODE_AGENT"
      The output should include "gga-reviewer"
    End

    It 'lets GGA-prefixed OpenCode environment variables override config'
      cat > .gga <<'EOF'
PROVIDER="opencode"
OPENCODE_VARIANT="low"
OPENCODE_AGENT="default-agent"
EOF
      When call env GGA_OPENCODE_VARIANT=max GGA_OPENCODE_AGENT=override-agent "$PROJECT_ROOT/bin/gga" config
      The output should include "max"
      The output should include "override-agent"
      The output should not include "low"
      The output should not include "default-agent"
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

    It 'resolves sibling lib/gga directory when installed LIB_DIR is stale'
      local install_root
      install_root=$(mktemp -d)
      mkdir -p "$install_root/bin/lib/gga"
      cp "$PROJECT_ROOT/bin/gga" "$install_root/bin/gga"
      cp "$PROJECT_ROOT/lib/providers.sh" "$install_root/bin/lib/gga/providers.sh"
      cp "$PROJECT_ROOT/lib/cache.sh" "$install_root/bin/lib/gga/cache.sh"
      cp "$PROJECT_ROOT/lib/pr_mode.sh" "$install_root/bin/lib/gga/pr_mode.sh"
      sed -i.bak 's|^LIB_DIR=.*|LIB_DIR="/mnt/c/Users/example/bin/lib/gga"|' "$install_root/bin/gga"
      chmod +x "$install_root/bin/gga"

      When call "$install_root/bin/gga" version
      The status should be success
      The output should include "gga v"
      rm -rf "$install_root"
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
