# shellcheck shell=bash

Describe 'providers.sh - kiro-cli'
  Include "$LIB_DIR/providers.sh"

  Describe 'validate_provider() - kiro-cli'
    It 'fails when q CLI is not available'
      command() {
        case "$2" in
          q) return 1 ;;
          *) return 1 ;;
        esac
      }

      When call validate_provider "kiro-cli"
      The status should be failure
      The output should include "Kiro CLI"
    End

    It 'succeeds when q CLI is available'
      command() {
        case "$2" in
          q) return 0 ;;
          *) return 0 ;;
        esac
      }

      When call validate_provider "kiro-cli"
      The status should be success
    End
  End

  Describe 'execute_kiro()'
    It 'calls q chat --no-interactive with the prompt'
      q() {
        echo "called:$*"
      }

      When call execute_kiro "review this code"
      The output should include "called:"
      The output should include "--no-interactive"
    End

    It 'returns exit status from q command'
      q() {
        return 42
      }

      When call execute_kiro "test"
      The status should eq 42
    End

    It 'returns output from q command'
      q() {
        echo "STATUS: PASSED"
        echo "All looks good."
      }

      When call execute_kiro "review"
      The output should include "STATUS: PASSED"
    End
  End

  Describe 'get_provider_info() - kiro-cli'
    It 'returns Kiro info string'
      When call get_provider_info "kiro-cli"
      The output should include "Kiro"
      The output should include "Amazon Q"
    End
  End
End
