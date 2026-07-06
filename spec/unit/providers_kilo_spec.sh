# shellcheck shell=bash

Describe 'providers.sh kilo support'
  Include "$LIB_DIR/providers.sh"

  Describe 'get_provider_info()'
    It 'returns info for kilo'
      When call get_provider_info "kilo"
      The output should include "Kilo CLI"
    End

    It 'returns info for kilo with model'
      When call get_provider_info "kilo:anthropic/claude-sonnet-4-5"
      The output should include "Kilo CLI"
      The output should include "model: anthropic/claude-sonnet-4-5"
    End
  End

  Describe 'execute_kilo()'
    kilo() {
      if [[ "$1" != "run" || "$2" != "--auto" ]]; then
        echo "unexpected kilo args: $*" >&2
        return 64
      fi
      shift 2
      if [[ "${1:-}" == "--model" ]]; then
        echo "MODEL:$2"
        shift 2
      fi
      if [[ $# -ne 0 ]]; then
        echo "unexpected kilo positional prompt: $*" >&2
        return 64
      fi
      cat
    }

    It 'executes kilo with default model'
      When call execute_kilo "" "test prompt"
      The status should be success
      The output should include "test prompt"
    End

    It 'executes kilo with specific model'
      When call execute_kilo "anthropic/claude-sonnet-4-5" "test prompt"
      The status should be success
      The output should include "MODEL:anthropic/claude-sonnet-4-5"
      The output should include "test prompt"
    End
  End

  Describe 'validate_provider() - kilo'
    It 'succeeds when kilo CLI is available'
      kilo() { return 0; }

      When call validate_provider "kilo"
      The status should be success
    End

    It 'fails when kilo CLI is unavailable'
      command() {
        case "$2" in
          kilo) return 1 ;;
          *) builtin command "$@" ;;
        esac
      }

      When call validate_provider "kilo"
      The status should be failure
      The output should include "Kilo CLI not found"
    End
  End
End
