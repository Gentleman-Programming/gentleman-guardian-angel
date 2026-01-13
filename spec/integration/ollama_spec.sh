# shellcheck shell=bash

# ============================================================================
# Ollama Integration Tests (LOCAL ONLY - NOT RUN IN CI)
# ============================================================================
# These tests require a real Ollama instance running.
# 
# Run locally with:
#   make docker-test-integration   # Uses Docker
#   OLLAMA_HOST=http://localhost:11434 shellspec spec/integration/ollama_spec.sh
#
# These tests are SKIPPED in CI because GPU-less runners are too slow.
# Unit tests with mocks cover the same logic in spec/unit/providers_spec.sh
# ============================================================================

Describe 'Ollama Integration'
  Include lib/providers.sh

  # Check if Ollama is available
  ollama_available() {
    [ -n "${OLLAMA_HOST:-}" ] && curl -sf "${OLLAMA_HOST}/api/tags" > /dev/null 2>&1
  }

  # Always skip if Ollama not available - these are LOCAL-ONLY tests
  skip_if_no_ollama() {
    ! ollama_available
  }

  Skip if "Ollama not available - run with OLLAMA_HOST=http://localhost:11434" skip_if_no_ollama

  Describe 'validate_ollama_host()'
    It 'accepts the Docker Ollama host'
      When call validate_ollama_host "${OLLAMA_HOST:-}"
      The status should be success
    End
  End

  Describe 'execute_ollama_api()'
    # Use qwen2.5:0.5b as it's small and fast for testing (~400MB)
    Parameters
      "qwen2.5:0.5b"
    End

    It "connects to real Ollama and gets a response"
      When call execute_ollama_api "$1" "Say hello in exactly 3 words" "${OLLAMA_HOST:-}"
      The status should be success
      The output should be present
    End

    It "handles model parameter correctly"
      When call execute_ollama_api "$1" "Reply with: OK" "${OLLAMA_HOST:-}"
      The status should be success
      The output should be present
    End
  End

  Describe 'execute_ollama_cli()'
    # This tests the CLI fallback path
    # Note: In Docker, we may not have ollama CLI, so this might be skipped

    skip_if_no_ollama_cli() {
      ! command -v ollama &> /dev/null
    }

    Skip if "Ollama CLI not available" skip_if_no_ollama_cli

    It "executes via CLI and strips ANSI codes"
      When call execute_ollama_cli "qwen2.5:0.5b" "Say hello"
      The status should be success
      The output should be present
      # Verify no ANSI escape codes in output
      The output should not include $'\033['
    End
  End

  Describe 'execute_ollama() routing'
    It "routes to API when python3 and curl are available"
      # In Docker container, both should be available
      When call execute_ollama "qwen2.5:0.5b" "Reply with: ROUTING_TEST"
      The status should be success
      The output should be present
    End
  End

  Describe 'STATUS parsing (Issue #6 fix verification)'
    # This is the core test for the bug fix
    # The AI should return STATUS: PASSED/FAILED without ANSI codes breaking parsing

    It "returns clean STATUS line that can be parsed"
      prompt='Review this code and respond with exactly: STATUS: PASSED

Code: const x = 1;'
      
      When call execute_ollama "qwen2.5:0.5b" "$prompt"
      The status should be success
      The output should be present
      # The output should be parseable (no ANSI codes breaking grep)
      # Note: We can't guarantee the AI will say PASSED, but output should be clean
    End

    It "output can be grepped for STATUS pattern"
      prompt='Respond with exactly this text and nothing else: STATUS: PASSED'
      result=$(execute_ollama "qwen2.5:0.5b" "$prompt" 2>&1)
      
      # The key test: can we grep the output without ANSI codes breaking it?
      When call echo "$result"
      The output should be present
      # Verify the output doesn't contain raw escape sequences
      The output should not match pattern $'*\033\\[*'
    End
  End

  Describe 'JSON payload handling'
    It "correctly escapes special characters in prompts"
      # Test with quotes and special chars that could break JSON
      prompt='Review this: const msg = "Hello \"World\""; // $HOME variable'
      
      When call execute_ollama_api "qwen2.5:0.5b" "$prompt" "${OLLAMA_HOST:-}"
      The status should be success
      # If JSON was malformed, Ollama would return an error
    End

    It "handles multiline prompts"
      prompt='Line 1
Line 2
Line 3'
      
      When call execute_ollama_api "qwen2.5:0.5b" "$prompt" "${OLLAMA_HOST:-}"
      The status should be success
    End

    It "handles unicode characters"
      prompt='Review: const emoji = "🎉"; const spanish = "señor";'
      
      When call execute_ollama_api "qwen2.5:0.5b" "$prompt" "${OLLAMA_HOST:-}"
      The status should be success
    End
  End

  Describe 'Error handling'
    It "fails gracefully with invalid model"
      When call execute_ollama_api "nonexistent-model-12345" "test" "${OLLAMA_HOST:-}"
      The status should be failure
      The stderr should be present
    End

    It "fails gracefully with invalid host"
      When call execute_ollama_api "qwen2.5:0.5b" "test" "http://invalid-host:99999"
      The status should be failure
      The stderr should include "Failed to connect"
    End
  End
End
