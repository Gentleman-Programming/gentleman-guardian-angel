# shellcheck shell=bash

Describe 'providers.sh cursor support'
  Include "$LIB_DIR/providers.sh"

  Describe 'get_provider_info()'
    It 'returns info for cursor'
      When call get_provider_info "cursor"
      The output should include "Cursor"
    End
  End

  Describe 'execute_cursor()'
    agent() {
      echo "args: $*"
      echo "prompt: $3"
    }

    It 'calls agent with --trust and --print flags'
      When call execute_cursor "review this code"
      The output should include "--trust"
      The output should include "--print"
    End

    It 'passes the prompt to agent'
      When call execute_cursor "review this code"
      The output should include "review this code"
    End

    It 'returns agent exit status on success'
      agent() { echo "ok"; return 0; }

      When call execute_cursor "test prompt"
      The status should be success
      The output should include "ok"
    End

    It 'returns agent exit status on failure'
      agent() { echo "error"; return 1; }

      When call execute_cursor "test prompt"
      The status should be failure
      The output should include "error"
    End

    It 'captures stderr in output'
      agent() {
        echo "stdout output"
        echo "stderr output" >&2
      }

      When call execute_cursor "test prompt"
      The output should include "stdout output"
      The output should include "stderr output"
    End
  End

  Describe 'execute_provider() routing to cursor'
    It 'routes cursor provider to execute_cursor'
      execute_cursor() {
        echo "CURSOR_CALLED: $1"
      }

      When call execute_provider "cursor" "test prompt"
      The output should include "CURSOR_CALLED: test prompt"
    End
  End

  Describe 'validate_provider() - cursor'
    It 'succeeds when agent CLI is available'
      agent() { return 0; }

      When call validate_provider "cursor"
      The status should be success
    End

    It 'fails when agent CLI is not available'
      command() {
        case "$2" in
          agent) return 1 ;;
          *) command "$@" ;;
        esac
      }

      When call validate_provider "cursor"
      The status should be failure
      The output should include "Cursor CLI not found"
      The output should include "cursor.com"
    End
  End
End
