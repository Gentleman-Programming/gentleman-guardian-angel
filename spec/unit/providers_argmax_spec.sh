# shellcheck shell=bash

# Tests for ARG_MAX fix - execute_provider_with_timeout should handle large prompts
# via temp files for CLI providers (claude, gemini, codex, opencode).
# Related issues: #77 (macOS), #87 (Windows), #58, #85

Describe 'providers.sh ARG_MAX handling'
  Include "$LIB_DIR/providers.sh"

  Describe 'execute_provider_with_timeout() - temp file for CLI providers'
    # Mock execute_with_timeout to capture how it's called
    execute_with_timeout() {
      local timeout="$1"
      local provider_name="$2"
      shift 2
      # Capture the command that would be executed
      echo "TIMEOUT:$timeout:$provider_name"
      echo "CMD:$*"
      # Simulate success
      return 0
    }

    # Mock provider commands
    claude() { cat; }
    codex() { cat; }
    opencode() { cat; }
    gemini() { cat; }

    It 'writes prompt to temp file for claude'
      When call execute_provider_with_timeout "claude" "test prompt" 300
      The output should include "TIMEOUT:300:Claude"
      # The command should use bash -c with cat to read from temp file
      The output should include "bash -c"
      The output should include "cat"
    End

    It 'writes prompt to temp file for codex'
      When call execute_provider_with_timeout "codex" "test prompt" 300
      The output should include "TIMEOUT:300:Codex"
      The output should include "bash -c"
    End

    It 'writes prompt to temp file for opencode without model'
      When call execute_provider_with_timeout "opencode" "test prompt" 300
      The output should include "TIMEOUT:300:OpenCode"
      The output should include "bash -c"
      # opencode run without positional args reads from stdin
      The output should include "opencode run"
    End

    It 'writes prompt to temp file for opencode with model'
      When call execute_provider_with_timeout "opencode:gpt-4" "test prompt" 300
      The output should include "TIMEOUT:300:OpenCode"
      The output should include "bash -c"
      The output should include "opencode run --model"
    End

    It 'writes prompt to temp file for gemini'
      When call execute_provider_with_timeout "gemini" "test prompt" 300
      The output should include "TIMEOUT:300:Gemini"
      The output should include "bash -c"
      The output should include "gemini -p -"
    End

    It 'handles large prompts without ARG_MAX errors'
      local large_prompt
      large_prompt=$(printf 'x%.0s' {1..400000})  # 400KB > ARG_MAX
      # This should not fail with "Argument list too long"
      When call execute_provider_with_timeout "claude" "$large_prompt" 300
      The output should include "TIMEOUT:300:Claude"
      The status should be success
    End

    It 'cleans up temp file after execution'
      local test_temp
      test_temp="$(mktemp -d)"
      TEMP="$test_temp"

      # Count temp files before
      local before_count
      before_count=$(ls -1 "${TEMP}/gga_prompt."* 2>/dev/null | wc -l || echo 0)

      When call execute_provider_with_timeout "claude" "test prompt" 300

      # Count temp files after
      local after_count
      after_count=$(ls -1 "${TEMP}/gga_prompt."* 2>/dev/null | wc -l || echo 0)

      # Should be the same (temp file was cleaned up)
      The value "$after_count" should eq "$before_count"
      rm -rf "$test_temp"
    End

    It 'cleans up temp file even on error'
      local test_temp
      test_temp="$(mktemp -d)"
      TEMP="$test_temp"

      # Mock execute_with_timeout to fail
      execute_with_timeout() {
        return 1
      }

      # Count temp files before
      local before_count
      before_count=$(ls -1 "${TEMP}/gga_prompt."* 2>/dev/null | wc -l || echo 0)

      When call execute_provider_with_timeout "claude" "test prompt" 300

      # Count temp files after - should still be cleaned up
      local after_count
      after_count=$(ls -1 "${TEMP}/gga_prompt."* 2>/dev/null | wc -l || echo 0)

      The value "$after_count" should eq "$before_count"
      # Exit code should be propagated
      The status should be failure
      rm -rf "$test_temp"
    End

    It 'passes model as positional argument to avoid shell injection'
      # Model with special characters should be passed safely as $2
      When call execute_provider_with_timeout "opencode:model-with-\$pecial-chars" "test prompt" 300
      The output should include "TIMEOUT:300:OpenCode"
      The output should include "bash -c"
      # The model should be passed as a separate argument, not interpolated in bash -c string
      The output should include "opencode run --model"
    End
  End

  Describe 'execute_provider_with_timeout() - API providers unchanged'
    # API-based providers (ollama, lmstudio) don't need temp files
    # because they use curl/HTTP and don't have argv limits

    It 'does not use temp file for ollama'
      # Mock execute_ollama to capture it was called directly
      execute_ollama() {
        echo "OLLAMA_CALLED:$1:$2"
      }
      validate_ollama_host() { return 0; }

      When call execute_provider_with_timeout "ollama:llama3" "test prompt" 300
      The output should include "OLLAMA_CALLED:llama3:test prompt"
    End

    It 'does not use temp file for lmstudio'
      execute_lmstudio() {
        echo "LMSTUDIO_CALLED:$1:$2"
      }
      validate_lmstudio_host() { return 0; }

      When call execute_provider_with_timeout "lmstudio:llama-3" "test prompt" 300
      The output should include "LMSTUDIO_CALLED:llama-3:test prompt"
    End

    It 'propagates exit code for ollama'
      # Mock execute_with_timeout to fail
      execute_with_timeout() {
        return 42
      }
      execute_ollama() {
        echo "OLLAMA_CALLED"
      }
      validate_ollama_host() { return 0; }

      When call execute_provider_with_timeout "ollama:llama3" "test prompt" 300
      The status should eq 42
    End

    It 'propagates exit code for lmstudio'
      # Mock execute_with_timeout to fail
      execute_with_timeout() {
        return 42
      }
      execute_lmstudio() {
        echo "LMSTUDIO_CALLED"
      }
      validate_lmstudio_host() { return 0; }

      When call execute_provider_with_timeout "lmstudio:llama-3" "test prompt" 300
      The status should eq 42
    End

    It 'propagates exit code for generic fallback'
      # Mock execute_with_timeout to fail
      execute_with_timeout() {
        return 42
      }
      execute_provider() {
        echo "FALLBACK_CALLED"
      }

      When call execute_provider_with_timeout "unknown-provider" "test prompt" 300
      The status should eq 42
    End
  End
End
