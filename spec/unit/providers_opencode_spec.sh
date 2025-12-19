# shellcheck shell=bash

Describe 'providers.sh opencode support'
  Include "$LIB_DIR/providers.sh"

  Describe 'get_provider_info()'
    It 'returns info for opencode'
      When call get_provider_info "opencode"
      The output should include "OpenCode"
    End

    It 'returns info for opencode with model'
      When call get_provider_info "opencode:gpt-4"
      The output should include "OpenCode"
      The output should include "model: gpt-4"
    End
  End

  Describe 'execute_opencode()'
    # Mock opencode command
    opencode() {
      if [[ "$1" == "run" ]]; then
        if [[ "${2:-}" == "--model" ]]; then
           echo "Run with model: $3"
        else
           echo "Run default"
        fi
        # Read stdin
        cat -
      fi
    }

    It 'executes opencode with default model'
      When call execute_opencode "" "test prompt"
      The output should include "Run default"
      The output should include "test prompt"
    End

    It 'executes opencode with specific model'
      When call execute_opencode "gpt-4" "test prompt"
      The output should include "Run with model: gpt-4"
      The output should include "test prompt"
    End
  End
End
