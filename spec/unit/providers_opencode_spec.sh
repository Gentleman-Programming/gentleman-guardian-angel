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

    It 'returns info with OpenCode variant and agent'
      OPENCODE_VARIANT="high"
      OPENCODE_AGENT="gga-reviewer"

      When call get_provider_info "opencode:gpt-4"

      The output should include "model: gpt-4"
      The output should include "variant: high"
      The output should include "agent: gga-reviewer"
      unset OPENCODE_VARIANT OPENCODE_AGENT
    End

    It 'prefers GGA-prefixed OpenCode overrides in provider info'
      OPENCODE_VARIANT="low"
      GGA_OPENCODE_VARIANT="max"
      OPENCODE_AGENT="default-agent"
      GGA_OPENCODE_AGENT="override-agent"

      When call get_provider_info "opencode"

      The output should include "variant: max"
      The output should include "agent: override-agent"
      The output should not include "variant: low"
      The output should not include "agent: default-agent"
      unset OPENCODE_VARIANT GGA_OPENCODE_VARIANT OPENCODE_AGENT GGA_OPENCODE_AGENT
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
        else
           echo "Run default"
        fi
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --variant)
              echo "Variant: $2"
              shift 2
              ;;
            --agent)
              echo "Agent: $2"
              shift 2
              ;;
            --)
              shift
              break
              ;;
            *)
              break
              ;;
          esac
        done
        echo "$*" # echo the prompt (remaining args)
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

    It 'passes OpenCode variant and agent flags'
      OPENCODE_VARIANT="high"
      OPENCODE_AGENT="gga-reviewer"

      When call execute_opencode "gpt-4" "test prompt"

      The output should include "Run with model: gpt-4"
      The output should include "Variant: high"
      The output should include "Agent: gga-reviewer"
      The output should include "test prompt"
      unset OPENCODE_VARIANT OPENCODE_AGENT
    End

    It 'prefers GGA-prefixed OpenCode flag overrides'
      OPENCODE_VARIANT="low"
      GGA_OPENCODE_VARIANT="max"
      OPENCODE_AGENT="default-agent"
      GGA_OPENCODE_AGENT="override-agent"

      When call execute_opencode "" "test prompt"

      The output should include "Variant: max"
      The output should include "Agent: override-agent"
      The output should not include "Variant: low"
      The output should not include "Agent: default-agent"
      unset OPENCODE_VARIANT GGA_OPENCODE_VARIANT OPENCODE_AGENT GGA_OPENCODE_AGENT
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
