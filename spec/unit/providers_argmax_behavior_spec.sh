# shellcheck shell=bash

# Behavioral tests for ARG_MAX prompt handoff. These tests execute the timeout
# wrapper with fake provider CLIs so we verify prompt bytes reach stdin instead
# of only asserting command-string shape.

Describe 'providers.sh ARG_MAX provider handoff behavior'
  Include "$LIB_DIR/providers.sh"

  setup() {
    export CI=true
    export GGA_NO_SPINNER=1
    TEST_BIN_DIR="$(mktemp -d)"
    ORIGINAL_PATH="$PATH"
    PATH="$TEST_BIN_DIR:$PATH"

    cat > "$TEST_BIN_DIR/claude" <<'FAKE'
#!/usr/bin/env bash
if [[ "$1" != "--print" ]]; then
  echo "unexpected claude args: $*" >&2
  exit 64
fi
cat
FAKE

    cat > "$TEST_BIN_DIR/gemini" <<'FAKE'
#!/usr/bin/env bash
if [[ "$1" != "-p" ]]; then
  echo "unexpected gemini args: $*" >&2
  exit 64
fi
cat
FAKE

    cat > "$TEST_BIN_DIR/codex" <<'FAKE'
#!/usr/bin/env bash
if [[ "$1" != "exec" || "$2" != "-" ]]; then
  echo "unexpected codex args: $*" >&2
  exit 64
fi
cat
FAKE

    cat > "$TEST_BIN_DIR/opencode" <<'FAKE'
#!/usr/bin/env bash
if [[ "$1" != "run" ]]; then
  echo "unexpected opencode command: $*" >&2
  exit 64
fi
shift
if [[ "${1:-}" == "--model" ]]; then
  echo "MODEL:$2"
  shift 2
fi
if [[ $# -ne 0 ]]; then
  echo "unexpected opencode positional prompt: $*" >&2
  exit 64
fi
cat
FAKE

    chmod +x "$TEST_BIN_DIR/claude" "$TEST_BIN_DIR/gemini" "$TEST_BIN_DIR/codex" "$TEST_BIN_DIR/opencode"
  }
  BeforeEach 'setup'

  cleanup() {
    PATH="$ORIGINAL_PATH"
    rm -rf "$TEST_BIN_DIR"
    unset CI
    unset GGA_NO_SPINNER
    unset TEST_BIN_DIR
    unset ORIGINAL_PATH
  }
  AfterEach 'cleanup'

  It 'passes the full prompt to claude via stdin'
    When call execute_provider_with_timeout "claude" $'line 1\nline 2' 5
    The status should be success
    The output should include "line 1"
    The output should include "line 2"
    The stderr should include "Waiting for Claude"
  End

  It 'passes the full prompt to gemini via stdin'
    When call execute_provider_with_timeout "gemini" $'line 1\nline 2' 5
    The status should be success
    The output should include "line 1"
    The output should include "line 2"
    The stderr should include "Waiting for Gemini"
  End

  It 'passes the full prompt to codex via stdin'
    When call execute_provider_with_timeout "codex" $'line 1\nline 2' 5
    The status should be success
    The output should include "line 1"
    The output should include "line 2"
    The stderr should include "Waiting for Codex"
  End

  It 'passes the full prompt to opencode via stdin without positional prompt args'
    When call execute_provider_with_timeout "opencode" $'line 1\nline 2' 5
    The status should be success
    The output should include "line 1"
    The output should include "line 2"
    The stderr should include "Waiting for OpenCode"
  End

  It 'passes opencode model separately and prompt via stdin'
    When call execute_provider_with_timeout "opencode:test-model" $'line 1\nline 2' 5
    The status should be success
    The output should include "MODEL:test-model"
    The output should include "line 1"
    The output should include "line 2"
    The stderr should include "Waiting for OpenCode"
  End
End
