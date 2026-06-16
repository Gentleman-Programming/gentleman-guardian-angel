# shellcheck shell=bash

# Tests for ARG_MAX fix - providers should handle large prompts via stdin/temp files
# Related issues: #77 (macOS), #87 (Windows), #58, #85

Describe 'providers.sh ARG_MAX handling'
  Include "$LIB_DIR/providers.sh"

  Describe 'execute_codex() - stdin support'
    # Mock codex command - reads prompt from stdin when using '-'
    codex() {
      if [[ "$1" == "exec" ]]; then
        shift
        if [[ "${1:-}" == "-" ]]; then
          # Read from stdin
          cat
        else
          echo "$*"
        fi
      fi
    }

    It 'passes prompt via stdin using - argument'
      When call execute_codex "test prompt"
      The output should include "test prompt"
    End

    It 'handles large prompts without ARG_MAX errors'
      local large_prompt
      large_prompt=$(printf 'x%.0s' {1..400000})  # 400KB > ARG_MAX
      When call execute_codex "$large_prompt"
      The length of output should be greater than 399999
    End
  End

  Describe 'execute_gemini() - temp file approach'
    # Mock gemini command
    gemini() {
      if [[ "$1" == "whoami" ]]; then
        return 0  # Pretend authenticated
      fi
      if [[ "$1" == "-p" ]]; then
        shift
        if [[ "${1:-}" == "-" ]]; then
          # Read from stdin
          cat
        else
          echo "$*"
        fi
      fi
    }

    It 'passes prompt via stdin to avoid ARG_MAX'
      When call execute_gemini "test prompt"
      The output should include "test prompt"
    End

    It 'handles large prompts without ARG_MAX errors'
      local large_prompt
      large_prompt=$(printf 'x%.0s' {1..400000})  # 400KB > ARG_MAX
      When call execute_gemini "$large_prompt"
      The length of output should be greater than 399999
    End

    It 'fails when not authenticated'
      gemini() {
        if [[ "$1" == "whoami" ]]; then
          return 1  # Not authenticated
        fi
      }
      When call execute_gemini "test prompt"
      The status should be failure
      The stderr should include "not authenticated"
    End
  End

  Describe 'execute_provider_with_timeout() - temp file for prompt'
    # Mock execute_with_timeout to capture how it's called
    execute_with_timeout() {
      local timeout="$1"
      local provider_name="$2"
      shift 2
      # Capture the command that would be executed
      echo "TIMEOUT:$timeout:$provider_name"
      echo "CMD:$*"
    }

    # Mock provider commands
    claude() { cat; }
    codex() { cat; }
    opencode() { cat; }
    gemini() { cat; }

    It 'writes prompt to temp file for claude'
      When call execute_provider_with_timeout "claude" "test prompt" 300
      The output should include "TIMEOUT:300:Claude"
      # The command should reference a temp file, not the prompt directly
      The output should include "bash -c"
      The output should include "cat"
    End

    It 'writes prompt to temp file for codex'
      When call execute_provider_with_timeout "codex" "test prompt" 300
      The output should include "TIMEOUT:300:Codex"
      The output should include "bash -c"
    End

    It 'writes prompt to temp file for opencode'
      When call execute_provider_with_timeout "opencode" "test prompt" 300
      The output should include "TIMEOUT:300:OpenCode"
      The output should include "bash -c"
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
      before_count=$(ls -1 "${TEMP:-${TMPDIR:-/tmp}}"/gga_prompt.* 2>/dev/null | wc -l || echo 0)
      
      When call execute_provider_with_timeout "claude" "test prompt" 300
      
      # Count temp files after
      local after_count
      after_count=$(ls -1 "${TEMP:-${TMPDIR:-/tmp}}"/gga_prompt.* 2>/dev/null | wc -l || echo 0)
      
      # Should be the same (temp file was cleaned up)
      The value "$after_count" should eq "$before_count"
      rm -rf "$test_temp"
    End
  End

  Describe 'execute_claude() - stdin pipe'
    # Mock claude command
    claude() {
      if [[ "$1" == "--print" ]]; then
        cat  # Read from stdin
      fi
    }

    It 'passes prompt via stdin pipe'
      When call execute_claude "test prompt"
      The output should include "test prompt"
    End

    It 'handles large prompts without ARG_MAX errors'
      local large_prompt
      large_prompt=$(printf 'x%.0s' {1..400000})  # 400KB > ARG_MAX
      When call execute_claude "$large_prompt"
      The length of output should be greater than 399999
    End
  End
End
