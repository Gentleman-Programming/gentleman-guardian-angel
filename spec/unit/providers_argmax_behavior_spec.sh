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
if [[ "$1" != "exec" || "$2" != "--output-last-message" || -z "${3:-}" || "$4" != "-" ]]; then
  echo "unexpected codex args: $*" >&2
  exit 64
fi
cat > "$3"
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
while [[ $# -gt 0 ]]; do
  case "$1" in
    --variant)
      echo "VARIANT:$2"
      shift 2
      ;;
    --agent)
      echo "AGENT:$2"
      shift 2
      ;;
    *)
      echo "unexpected opencode positional prompt: $*" >&2
      exit 64
      ;;
  esac
done
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
    unset OPENCODE_VARIANT GGA_OPENCODE_VARIANT OPENCODE_AGENT GGA_OPENCODE_AGENT
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

  It 'passes opencode variant and agent flags while keeping prompt on stdin'
    OPENCODE_VARIANT="high"
    OPENCODE_AGENT="gga-reviewer"

    When call execute_provider_with_timeout "opencode:test-model" $'line 1\nline 2' 5

    The status should be success
    The output should include "MODEL:test-model"
    The output should include "VARIANT:high"
    The output should include "AGENT:gga-reviewer"
    The output should include "line 1"
    The output should include "line 2"
    The stderr should include "Waiting for OpenCode"
  End

  It 'prefers GGA-prefixed opencode flag overrides with stdin handoff'
    OPENCODE_VARIANT="low"
    GGA_OPENCODE_VARIANT="max"
    OPENCODE_AGENT="default-agent"
    GGA_OPENCODE_AGENT="override-agent"

    When call execute_provider_with_timeout "opencode" "test prompt" 5

    The status should be success
    The output should include "VARIANT:max"
    The output should include "AGENT:override-agent"
    The output should include "test prompt"
    The output should not include "VARIANT:low"
    The output should not include "AGENT:default-agent"
    The stderr should include "Waiting for OpenCode"
  End
End
