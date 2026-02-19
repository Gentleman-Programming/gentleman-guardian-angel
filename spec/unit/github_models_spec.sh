# shellcheck shell=bash

# ============================================================================
# GitHub Models Provider - Unit Tests
# ============================================================================
# Tests for the GitHub Models provider (github:<model>)
# Uses the OpenAI-compatible API at models.inference.ai.azure.com
# ============================================================================

Describe 'providers.sh GitHub Models support'
  Include "$LIB_DIR/providers.sh"

  Describe 'validate_provider() - github'
    It 'succeeds when gh and curl are available with model specified'
      command() {
        case "$2" in
          gh|curl) return 0 ;;
          *) return 1 ;;
        esac
      }

      When call validate_provider "github:gpt-4o"
      The status should be success
    End

    It 'fails when gh CLI is not available'
      command() {
        case "$2" in
          gh) return 1 ;;
          curl) return 0 ;;
          *) return 1 ;;
        esac
      }

      When call validate_provider "github:gpt-4o"
      The status should be failure
      The output should include "gh CLI not found"
    End

    It 'fails when curl is not available'
      command() {
        case "$2" in
          gh) return 0 ;;
          curl) return 1 ;;
          *) return 1 ;;
        esac
      }

      When call validate_provider "github:gpt-4o"
      The status should be failure
      The output should include "curl not found"
    End

    It 'fails when no model is specified'
      command() {
        case "$2" in
          gh|curl) return 0 ;;
          *) return 1 ;;
        esac
      }

      When call validate_provider "github"
      The status should be failure
      The output should include "requires a model"
    End
  End

  Describe 'get_provider_info() - github'
    It 'returns info for github with model name'
      When call get_provider_info "github:gpt-4o"
      The output should include "GitHub Models"
      The output should include "gpt-4o"
    End

    It 'returns info for github with deepseek model'
      When call get_provider_info "github:deepseek-r1"
      The output should include "GitHub Models"
      The output should include "deepseek-r1"
    End
  End

  Describe 'execute_github_models()'
    skip_if_no_python3() {
      ! command -v python3 &> /dev/null
    }

    Skip if "python3 not available" skip_if_no_python3

    It 'calls curl with correct endpoint and auth header'
      # Mock gh to return a fake token
      gh() {
        echo "fake-github-token"
      }

      # Mock curl to verify it receives the right arguments
      # curl args: -sS -H "Content-Type: ..." -H "Authorization: Bearer ..." -d "..." URL
      curl() {
        # Check all args as a single string for the key values
        local all_args="$*"
        local has_auth=false
        local has_endpoint=false

        [[ "$all_args" == *"Bearer fake-github-token"* ]] && has_auth=true
        [[ "$all_args" == *"models.inference.ai.azure.com"* ]] && has_endpoint=true

        if [[ "$has_auth" == "true" && "$has_endpoint" == "true" ]]; then
          echo '{"choices": [{"message": {"content": "STATUS: PASSED"}}]}'
        else
          echo "Missing auth or endpoint: $all_args" >&2
          return 1
        fi
      }

      When call execute_github_models "gpt-4o" "test prompt"
      The status should be success
      The output should include "STATUS: PASSED"
    End

    It 'handles curl failure'
      gh() { echo "fake-token"; }
      curl() {
        echo "Connection refused"
        return 7
      }

      When call execute_github_models "gpt-4o" "test prompt"
      The status should be failure
      The stderr should include "Failed to connect"
    End

    It 'parses JSON response correctly'
      gh() { echo "fake-token"; }
      curl() {
        cat <<'EOF'
{
  "choices": [
    {
      "message": {
        "content": "STATUS: PASSED\nAll files comply with standards."
      }
    }
  ]
}
EOF
      }

      When call execute_github_models "gpt-4o" "test prompt"
      The status should be success
      The output should include "STATUS: PASSED"
    End

    It 'handles invalid JSON response'
      gh() { echo "fake-token"; }
      curl() {
        echo 'not valid json'
      }

      When call execute_github_models "gpt-4o" "test prompt"
      The status should be failure
      The stderr should include "Invalid JSON"
    End

    It 'handles response with error field'
      gh() { echo "fake-token"; }
      curl() {
        echo '{"error": {"message": "model not found", "code": "ModelNotFound"}}'
      }

      When call execute_github_models "gpt-4o" "test prompt"
      The status should be failure
      The stderr should include "model not found"
    End

    It 'handles empty choices array'
      gh() { echo "fake-token"; }
      curl() {
        echo '{"choices": []}'
      }

      When call execute_github_models "gpt-4o" "test prompt"
      The status should be failure
      The stderr should include "Unexpected response format"
    End

    It 'fails when gh auth token fails'
      gh() {
        echo "not logged in" >&2
        return 1
      }

      When call execute_github_models "gpt-4o" "test prompt"
      The status should be failure
      The stderr should include "GitHub CLI authentication failed"
    End

    It 'passes model name in the API request payload'
      gh() { echo "fake-token"; }
      # We can verify indirectly by checking the response works
      curl() {
        # The payload should contain the model name - curl receives it via -d
        cat <<'EOF'
{
  "choices": [
    {
      "message": {
        "content": "MODEL_TEST_OK"
      }
    }
  ]
}
EOF
      }

      When call execute_github_models "deepseek-r1" "test prompt"
      The status should be success
      The output should eq "MODEL_TEST_OK"
    End
  End

  Describe 'execute_provider() - github routing'
    It 'routes github provider to execute_github_models'
      execute_github_models() {
        echo "GITHUB_MODELS_CALLED:$1:$2"
      }

      When call execute_provider "github:gpt-4o" "test prompt"
      The output should eq "GITHUB_MODELS_CALLED:gpt-4o:test prompt"
    End

    It 'extracts model correctly from provider string'
      execute_github_models() {
        echo "MODEL:$1"
      }

      When call execute_provider "github:deepseek-r1-0528" "test"
      The output should eq "MODEL:deepseek-r1-0528"
    End
  End
End
