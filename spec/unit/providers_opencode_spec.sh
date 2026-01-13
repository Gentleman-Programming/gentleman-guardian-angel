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
    # Mock opencode command - accepts prompt as positional argument
    opencode() {
      if [[ "$1" == "run" ]]; then
        shift # remove "run"
        if [[ "${1:-}" == "--model" ]]; then
           local model="$2"
           shift 2 # remove "--model" and model name
           echo "Run with model: $model"
           echo "$*" # echo the prompt (remaining args)
        else
           echo "Run default"
           echo "$*" # echo the prompt (remaining args)
        fi
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

  Describe 'validate_provider() - opencode'
    It 'succeeds when opencode CLI is available'
      # Mock opencode to pretend it exists
      opencode() { return 0; }

      When call validate_provider "opencode"
      The status should be success
    End

    It 'succeeds when opencode has a model specified'
      # Mock opencode to pretend it exists
      opencode() { return 0; }

      When call validate_provider "opencode:gpt-4"
      The status should be success
    End

    It 'succeeds with anthropic model format'
      # Mock opencode to pretend it exists
      opencode() { return 0; }

      When call validate_provider "opencode:anthropic/claude-sonnet-4"
      The status should be success
    End
  End
End
