# shellcheck shell=bash

# ============================================================================
# Kiro CLI (Amazon Q Developer) Integration Tests (LOCAL ONLY - NOT RUN IN CI)
# ============================================================================
# These tests require Kiro CLI (Amazon Q Developer) installed and authenticated.
#
# Install: https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/command-line.html
# Auth:    q login
#
# Run locally with:
#   shellspec spec/integration/kiro_spec.sh
# ============================================================================

Describe 'Kiro CLI Integration'
  Include "$LIB_DIR/providers.sh"

  # Skip tests if q CLI is not available
  skip_if_no_kiro() {
    ! command -v kiro-cli &> /dev/null
  }

  Skip if "Kiro CLI (q) not available" skip_if_no_kiro

  Describe 'validate_provider()'
    It 'validates kiro provider successfully'
      When call validate_provider "kiro-cli"
      The status should be success
    End
  End

  Describe 'execute_kiro()'
    It 'connects to Kiro and gets a response'
      When call execute_kiro "Say hello in exactly 3 words"
      The status should be success
      The output should be present
    End
  End

  Describe 'STATUS parsing'
    It 'returns clean STATUS line that can be parsed'
      When call execute_kiro "Respond with exactly: STATUS: PASSED"
      The status should be success
      The output should include "STATUS:"
    End
  End
End
