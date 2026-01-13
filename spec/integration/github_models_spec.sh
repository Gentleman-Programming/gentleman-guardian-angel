# shellcheck shell=bash

# ============================================================================
# GitHub Models Integration Tests (LOCAL ONLY - NOT RUN IN CI)
# ============================================================================
# These tests require:
#   - gh CLI installed and authenticated
#   - jq installed (required for JSON payload construction)
#   - GITHUB_TOKEN with GitHub Models access
#
# Run locally with:
#   shellspec spec/integration/github_models_spec.sh
# ============================================================================

Describe 'GitHub Models Integration'
  Include lib/providers.sh

  github_models_available() {
    command -v gh &> /dev/null && \
    command -v jq &> /dev/null && \
    gh auth status &> /dev/null
  }

  skip_if_no_github() {
    ! github_models_available
  }

  Skip if "GitHub CLI/jq not available or not authenticated" skip_if_no_github

  Parameters
    "gpt-4.1"
  End

  Describe 'execute_github_models()'
    It "connects to GitHub Models and gets a response"
      When call execute_github_models "$1" "Say hello in exactly 3 words"
      The status should be success
      The output should be present
    End
  End

  Describe 'JSON payload handling'
    It "correctly escapes special characters in prompts"
      prompt='Review this: const msg = "Hello \"World\""; // $HOME variable'

      When call execute_github_models "$1" "$prompt"
      The status should be success
      The output should be present
    End

    It "handles multiline prompts"
      prompt='Line 1
Line 2
Line 3'

      When call execute_github_models "$1" "$prompt"
      The status should be success
      The output should be present
    End

    It "handles unicode characters"
      prompt='Translate to English: "Hola señor 🎉"'

      When call execute_github_models "$1" "$prompt"
      The status should be success
      The output should be present
    End
  End

  Describe 'STATUS parsing'
    It "returns clean STATUS line that can be parsed"
      prompt='Respond with exactly this text and nothing else: STATUS: PASSED'

      When call execute_github_models "$1" "$prompt"
      The status should be success
      The output should include "STATUS: PASSED"
    End
  End

  Describe 'Error handling'
    It "fails gracefully with invalid model"
      When call execute_github_models "nonexistent-model-12345" "test"
      The status should be failure
      The stderr should be present
    End

    It "fails gracefully when token cannot be retrieved"
      gh() { return 1; }

      When call execute_github_models "$1" "test"
      The status should be failure
      The stderr should include "Not authenticated"
    End
  End
End
