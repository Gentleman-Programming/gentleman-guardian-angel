# shellcheck shell=bash

# ============================================================================
# Cursor Integration Tests (LOCAL ONLY - NOT RUN IN CI)
# ============================================================================
# These tests require Cursor CLI (agent) installed and configured.
#
# Run locally with:
#   shellspec spec/integration/cursor_spec.sh
# ============================================================================

Describe 'Cursor Integration'
  Include "$LIB_DIR/providers.sh"

  # Skip tests if Cursor agent CLI is not available
  skip_if_no_cursor() {
    ! command -v agent &> /dev/null
  }

  Skip if "Cursor agent CLI not available" skip_if_no_cursor

  Describe 'validate_provider()'
    It 'validates cursor provider successfully'
      When call validate_provider "cursor"
      The status should be success
    End
  End

  Describe 'execute_cursor()'
    It 'connects to Cursor and gets a response'
      When call execute_cursor "Say hello in exactly 3 words"
      The status should be success
      The output should be present
    End
  End

  Describe 'execute_provider() routing'
    It 'routes cursor provider end-to-end'
      When call execute_provider "cursor" "Reply with: OK"
      The status should be success
      The output should be present
    End
  End

  Describe 'STATUS parsing'
    It 'returns clean STATUS line that can be parsed'
      When call execute_cursor "Respond with exactly: STATUS: PASSED"
      The status should be success
      The output should include "STATUS:"
    End
  End
End
