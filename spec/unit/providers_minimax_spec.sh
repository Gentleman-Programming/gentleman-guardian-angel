# shellcheck shell=bash

Describe 'providers.sh MiniMax support'
  Include "$LIB_DIR/providers.sh"

  Describe 'validate_provider() - minimax'
    It 'fails when MINIMAX_API_KEY is not set'
      unset MINIMAX_API_KEY

      When call validate_provider "minimax"
      The status should be failure
      The output should include "MINIMAX_API_KEY not set"
    End

    It 'succeeds when MINIMAX_API_KEY, curl, and python3 are available'
      MINIMAX_API_KEY="fake-key"
      command() {
        case "$2" in
          curl|python3) return 0 ;;
          *) return 1 ;;
        esac
      }

      When call validate_provider "minimax:MiniMax-M3"
      The status should be success
    End
  End

  Describe 'get_provider_info() - minimax'
    It 'uses default model when none is specified'
      When call get_provider_info "minimax"
      The output should include "MiniMax"
      The output should include "MiniMax-M3"
    End

    It 'returns info for explicit model'
      When call get_provider_info "minimax:MiniMax-M2.7"
      The output should include "MiniMax"
      The output should include "MiniMax-M2.7"
    End
  End

  Describe 'execute_minimax()'
    skip_if_no_python3() {
      ! command -v python3 &> /dev/null
    }

    Skip if "python3 not available" skip_if_no_python3

    It 'sends JSON payload through stdin instead of argv'
      MINIMAX_API_KEY="fake-key"
      curl() {
        local args="$*"
        local payload config_file=""
        payload=$(cat)
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --config)
              config_file="$2"
              shift 2
              ;;
            *) shift ;;
          esac
        done
        [[ -n "$config_file" && -f "$config_file" ]] || { echo "missing curl config" >&2; return 64; }
        grep -q 'Authorization: Bearer fake-key' "$config_file" || { echo "missing auth in config" >&2; return 64; }
        [[ "$args" != *"Authorization: Bearer fake-key"* ]] || { echo "auth leaked through argv" >&2; return 64; }
        [[ "$args" == *"--data-binary @-"* ]] || { echo "missing stdin payload flag" >&2; return 64; }
        for arg in "$@"; do
          [[ "$arg" != "-d" && "$arg" != "--data" && "$arg" != "--data-raw" ]] || { echo "payload passed through argv" >&2; return 64; }
        done
        [[ "$payload" == *"large review prompt"* ]] || { echo "missing prompt in stdin payload" >&2; return 64; }
        echo '{"choices":[{"message":{"content":"STATUS: PASSED"}}]}'
      }

      When call execute_minimax "MiniMax-M3" "large review prompt"
      The status should be success
      The output should include "STATUS: PASSED"
    End

    It 'handles API error responses'
      MINIMAX_API_KEY="fake-key"
      curl() {
        echo '{"error":{"message":"invalid api key"}}'
      }

      When call execute_minimax "MiniMax-M3" "test prompt"
      The status should be failure
      The stderr should include "invalid api key"
    End

    It 'handles curl failures'
      MINIMAX_API_KEY="fake-key"
      curl() {
        echo "Connection refused"
        return 7
      }

      When call execute_minimax "MiniMax-M3" "test prompt"
      The status should be failure
      The stderr should include "Failed to connect to MiniMax API"
    End

    It 'handles invalid JSON responses'
      MINIMAX_API_KEY="fake-key"
      curl() {
        echo 'not valid json'
      }

      When call execute_minimax "MiniMax-M3" "test prompt"
      The status should be failure
      The stderr should include "Invalid JSON response from MiniMax"
    End

    It 'handles MiniMax base_resp errors'
      MINIMAX_API_KEY="fake-key"
      curl() {
        echo '{"base_resp":{"status_code":1001,"status_msg":"quota exceeded"}}'
      }

      When call execute_minimax "MiniMax-M3" "test prompt"
      The status should be failure
      The stderr should include "quota exceeded"
    End

    It 'handles empty choices'
      MINIMAX_API_KEY="fake-key"
      curl() {
        echo '{"choices":[]}'
      }

      When call execute_minimax "MiniMax-M3" "test prompt"
      The status should be failure
      The stderr should include "Unexpected response format from MiniMax"
    End

    It 'handles empty content'
      MINIMAX_API_KEY="fake-key"
      curl() {
        echo '{"choices":[{"message":{"content":""}}]}'
      }

      When call execute_minimax "MiniMax-M3" "test prompt"
      The status should be failure
      The stderr should include "Empty response from MiniMax"
    End
  End
End
