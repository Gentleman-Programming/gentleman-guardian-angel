# shellcheck shell=bash

# ============================================================================
# OpenCode Integration Tests (LOCAL ONLY - NOT RUN IN CI)
# ============================================================================
# These tests require OpenCode CLI installed and configured.
#
# Run locally with:
#   shellspec spec/integration/opencode_spec.sh
# ============================================================================

Describe 'OpenCode Integration'
  Include "$LIB_DIR/providers.sh"

  # Skip tests if OpenCode is not available or not responding
  skip_if_no_opencode() {
    # Check if command exists
    ! command -v opencode &> /dev/null && return 0
    # Check if service is responding (quick test)
    local test_result
    test_result=$(opencode --prompt "test" 2>&1) || return 0
    [[ "$test_result" == *"Unable to connect"* ]] && return 0
    [[ "$test_result" == *"Error"* ]] && return 0
    return 1
  }

  Skip if "OpenCode not available or not responding" skip_if_no_opencode

  Describe 'validate_provider()'
    It 'validates opencode provider successfully'
      When call validate_provider "opencode"
      The status should be success
    End

    It 'validates opencode with model successfully'
      When call validate_provider "opencode:anthropic/claude-sonnet-4"
      The status should be success
    End
  End

  Describe 'execute_opencode()'
    It 'connects to OpenCode and gets a response'
      When call execute_opencode "" "Say hello in exactly 3 words"
      The status should be success
      The output should be present
    End

    It 'works with specific model'
      When call execute_opencode "anthropic/claude-sonnet-4" "Reply with: OK"
      The status should be success
      The output should be present
    End
  End

  Describe 'STATUS parsing'
    It 'returns clean STATUS line that can be parsed'
      When call execute_opencode "" "Respond with exactly: STATUS: PASSED"
      The status should be success
      The output should include "STATUS:"
    End
  End
End
