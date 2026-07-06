# shellcheck shell=bash

Describe 'providers.sh kiro support'
  Include "$LIB_DIR/providers.sh"

  Describe 'get_provider_info()'
    It 'returns info for kiro'
      When call get_provider_info "kiro"
      The output should include "Kiro CLI"
    End
  End

  Describe 'execute_kiro()'
    kiro-cli() {
      if [[ "$1" != "chat" || "$2" != "--no-interactive" ]]; then
        echo "unexpected kiro args: $*" >&2
        return 64
      fi
      shift 2
      if [[ $# -ne 1 ]]; then
        echo "missing kiro headless instruction: $*" >&2
        return 64
      fi
      echo "INSTRUCTION:$1"
      cat
    }

    It 'executes kiro with prompt through stdin and a small headless instruction'
      When call execute_kiro "test prompt"
      The status should be success
      The output should include "INSTRUCTION:Review the complete GGA prompt provided on stdin"
      The output should include "test prompt"
    End
  End

  Describe 'validate_provider() - kiro'
    It 'succeeds when kiro CLI is available'
      kiro-cli() { return 0; }

      When call validate_provider "kiro"
      The status should be success
    End

    It 'fails when kiro CLI is unavailable'
      command() {
        case "$2" in
          kiro-cli) return 1 ;;
          *) builtin command "$@" ;;
        esac
      }

      When call validate_provider "kiro"
      The status should be failure
      The output should include "Kiro CLI not found"
    End

    It 'rejects inline model selection'
      kiro-cli() { return 0; }

      When call validate_provider "kiro:claude-sonnet-4"
      The status should be failure
      The output should include "does not support inline model selection"
    End
  End
End
