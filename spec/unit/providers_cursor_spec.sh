# shellcheck shell=bash

Describe 'providers.sh cursor support'
  Include "$LIB_DIR/providers.sh"

  Describe 'get_provider_info()'
    It 'returns info for cursor'
      When call get_provider_info "cursor"
      The output should include "Cursor Agent"
    End

    It 'returns info for cursor with model'
      When call get_provider_info "cursor:composer-2"
      The output should include "Cursor Agent"
      The output should include "model: composer-2"
    End
  End

  Describe 'execute_cursor()'
    cursor-agent() {
      if [[ "$1" != "-p" ]]; then
        echo "unexpected cursor args: $*" >&2
        return 64
      fi
      shift
      if [[ "${1:-}" == "--model" ]]; then
        echo "Model: $2"
        shift 2
      fi
      if [[ "${1:-}" != "--output-format" || "${2:-}" != "text" ]]; then
        echo "missing output format: $*" >&2
        return 64
      fi
      cat
    }

    It 'executes cursor with default model'
      When call execute_cursor "" "test prompt"
      The status should be success
      The output should include "test prompt"
    End

    It 'executes cursor with specific model'
      When call execute_cursor "composer-2" "test prompt"
      The status should be success
      The output should include "Model: composer-2"
      The output should include "test prompt"
    End

    It 'falls back to legacy agent binary when cursor-agent is unavailable'
      local test_bin original_path
      test_bin=$(mktemp -d)
      original_path="$PATH"
      cat > "$test_bin/agent" <<'FAKE'
#!/bin/bash
if [[ "$1" != "-p" ]]; then
  echo "unexpected args: $*" >&2
  exit 64
fi
/bin/cat
FAKE
      chmod +x "$test_bin/agent"
      unset -f cursor-agent
      PATH="$test_bin"

      When call execute_cursor "" "test prompt"

      The status should be success
      The output should include "test prompt"
      PATH="$original_path"
      rm -rf "$test_bin"
    End
  End

  Describe 'validate_provider() - cursor'
    It 'succeeds when cursor-agent CLI is available'
      cursor-agent() { return 0; }

      When call validate_provider "cursor"
      The status should be success
    End

  End
End
