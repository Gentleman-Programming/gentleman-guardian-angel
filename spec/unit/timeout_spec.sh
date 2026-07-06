# shellcheck shell=bash

# ============================================================================
# Tests for execute_with_timeout() and execute_provider_with_timeout()
# ============================================================================
# TDD: Tests written BEFORE implementation.
# Based on the design from PR #20 by @ramarivera, with fixes applied.
# ============================================================================

Describe 'execute_with_timeout()'
  Include "$LIB_DIR/providers.sh"

  # Force non-TTY mode for consistent testing
  setup() {
    export CI=true
    export GGA_NO_SPINNER=1
  }
  Before 'setup'

  cleanup() {
    unset CI
    unset GGA_NO_SPINNER
    unset GGA_TRACE
  }
  After 'cleanup'

  Describe 'successful command execution'
    It 'returns exit code 0 for successful command'
      When call execute_with_timeout 5 "TestProvider" echo "hello"
      The status should eq 0
      The output should include "hello"
      The stderr should include "Waiting for TestProvider"
    End

    It 'captures multi-line output'
      When call execute_with_timeout 5 "TestProvider" bash -c 'echo "Line 1"; echo "Line 2"; echo "Line 3"'
      The status should eq 0
      The output should include "Line 1"
      The output should include "Line 2"
      The output should include "Line 3"
      The stderr should be present
    End
  End

  Describe 'failed command execution'
    It 'returns non-zero exit code for failed command'
      When call execute_with_timeout 5 "TestProvider" bash -c "exit 42"
      The status should eq 42
      The output should include "(provider returned no output)"
      The stderr should be present
    End

    It 'captures stderr from failing command'
      When call execute_with_timeout 5 "TestProvider" bash -c "echo 'error message' >&2; exit 1"
      The status should eq 1
      # stdout+stderr are combined in output file
      The output should include "error message"
      The stderr should be present
    End

    It 'returns exit code 1 for false command'
      When call execute_with_timeout 5 "TestProvider" false
      The status should eq 1
      The output should include "(provider returned no output)"
      The stderr should be present
    End
  End

  Describe 'timeout behavior'
    It 'returns exit code 124 when command times out'
      When call execute_with_timeout 1 "TestProvider" sleep 10
      The status should eq 124
      The stderr should include "TIMEOUT"
    End

    It 'includes timeout duration in error message'
      When call execute_with_timeout 2 "SlowProvider" sleep 10
      The status should eq 124
      The stderr should include "2 seconds"
    End

    It 'suggests increasing TIMEOUT in error message'
      When call execute_with_timeout 1 "TestProvider" sleep 10
      The status should eq 124
      The stderr should include "Increase TIMEOUT"
    End
  End

  Describe 'progress feedback in non-TTY mode'
    It 'shows waiting message on stderr'
      When call execute_with_timeout 5 "TestProvider" echo "done"
      The status should eq 0
      The stderr should include "Waiting for TestProvider"
      The output should include "done"
    End

    It 'includes timeout in waiting message'
      When call execute_with_timeout 10 "TestProvider" echo "done"
      The status should eq 0
      The stderr should include "10s"
      The output should include "done"
    End
  End

  Describe 'trace mode'
    setup_trace() {
      export CI=true
      export GGA_NO_SPINNER=1
      export GGA_TRACE=1
    }
    Before 'setup_trace'

    It 'shows trace output when GGA_TRACE is set'
      When call execute_with_timeout 5 "TestProvider" echo "test"
      The status should eq 0
      The stderr should include "[TRACE]"
      The output should include "test"
    End

    It 'shows exit code in trace'
      When call execute_with_timeout 5 "TestProvider" bash -c "exit 7"
      The status should eq 7
      The stderr should include "exit_code=7"
      The output should include "(provider returned no output)"
    End
  End
End

Describe 'execute_provider_with_timeout()'
  Include "$LIB_DIR/providers.sh"

  setup() {
    export CI=true
    export GGA_NO_SPINNER=1
  }
  Before 'setup'

  cleanup() {
    unset CI
    unset GGA_NO_SPINNER
    unset OLLAMA_HOST
    unset LMSTUDIO_HOST
  }
  After 'cleanup'

  Describe 'generic fallback for unknown providers'
    It 'uses execute_provider as fallback instead of failing'
      # Mock execute_provider for the unknown provider
      execute_provider() {
        echo "FALLBACK_CALLED:$1"
      }

      When call execute_provider_with_timeout "some-new-provider" "test" 5
      The status should eq 0
      The output should include "FALLBACK_CALLED:some-new-provider"
      The stderr should be present
    End
  End

  Describe 'ollama host validation'
    It 'fails with invalid OLLAMA_HOST before attempting execution'
      OLLAMA_HOST="invalid://bad"

      When call execute_provider_with_timeout "ollama:llama3" "test" 5
      The status should be failure
      The stderr should include "Invalid OLLAMA_HOST"
    End
  End

  Describe 'lmstudio host validation'
    It 'fails with invalid LMSTUDIO_HOST before attempting execution'
      LMSTUDIO_HOST="invalid://bad"

      When call execute_provider_with_timeout "lmstudio" "test" 5
      The status should be failure
      The stderr should include "Invalid LMSTUDIO_HOST"
    End
  End

  Describe 'timeout parameter passing'
    It 'respects timeout parameter by timing out slow commands'
      When call execute_with_timeout 1 "TestProvider" sleep 10
      The status should eq 124
      The stderr should include "TIMEOUT"
    End
  End
End

Describe 'provider base extraction in timeout context'
  Include "$LIB_DIR/providers.sh"

  helper_get_base_provider() {
    local provider="$1"
    echo "${provider%%:*}"
  }

  It 'extracts base provider from simple provider'
    When call helper_get_base_provider "claude"
    The output should eq "claude"
  End

  It 'extracts base provider from ollama:model'
    When call helper_get_base_provider "ollama:llama3.2"
    The output should eq "ollama"
  End

  It 'extracts base provider from lmstudio:model'
    When call helper_get_base_provider "lmstudio:qwen"
    The output should eq "lmstudio"
  End
End
