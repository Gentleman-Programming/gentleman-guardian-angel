# shellcheck shell=bash

# ============================================================================
# GitHub Models Integration Tests (LOCAL ONLY - NOT RUN IN CI)
# ============================================================================
# These tests require:
#   - gh CLI installed and authenticated
#   - GITHUB_TOKEN with GitHub Models access
#
# Run locally with:
#   shellspec spec/integration/github_models_spec.sh
# ============================================================================

Describe 'GitHub Models Integration'
  Include lib/providers.sh

  # Check if GitHub Models is available
  github_models_available() {
    command -v gh &> /dev/null && gh auth status &> /dev/null 2>&1
  }

  skip_if_no_github_models() {
    ! github_models_available
  }

  Skip if "GitHub CLI not available or not authenticated" skip_if_no_github_models

  Describe 'execute_github_models()'
    It "connects to GitHub Models and gets a response"
      When call execute_github_models "gpt-4o-mini" "Say hello in exactly 3 words"
      The status should be success
      The output should be present
    End
  End

  Describe 'STATUS parsing'
    It "returns clean STATUS line that can be parsed"
      When call execute_github_models "gpt-4o-mini" "Respond with exactly: STATUS: PASSED"
      The status should be success
      The output should include "STATUS:"
    End
  End

  Describe 'Error handling'
    It "fails gracefully with invalid model"
      When call execute_github_models "nonexistent-model-12345" "test"
      The status should be failure
      The stderr should be present
    End
  End
End
