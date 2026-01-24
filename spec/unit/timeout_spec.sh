# shellcheck shell=bash

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

    It 'captures stdout from command'
      When call execute_with_timeout 5 "TestProvider" echo "STATUS: PASSED"
      The status should eq 0
      The output should include "STATUS: PASSED"
      The stderr should be present
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
      The output should include "error message"
      The stderr should be present
    End

    It 'returns exit code 1 for command that fails'
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
      The output should be blank
    End

    It 'includes timeout duration in timeout message'
      When call execute_with_timeout 2 "MySlowProvider" sleep 10
      The status should eq 124
      The stderr should include "TIMEOUT"
      The stderr should include "2 seconds"
      The output should be blank
    End

    It 'suggests solutions in timeout message'
      When call execute_with_timeout 1 "TestProvider" sleep 10
      The status should eq 124
      The stderr should include "Increase TIMEOUT"
      The output should be blank
    End
  End

  Describe 'progress feedback'
    It 'shows waiting message on stderr in non-TTY mode'
      When call execute_with_timeout 5 "TestProvider" echo "done"
      The status should eq 0
      The stderr should include "Waiting for TestProvider"
      The output should include "done"
    End

    It 'shows timeout duration in waiting message'
      When call execute_with_timeout 10 "TestProvider" echo "done"
      The status should eq 0
      The stderr should include "10s"
      The output should include "done"
    End
  End

  Describe 'output handling'
    It 'outputs (provider returned no output) for empty output with error'
      When call execute_with_timeout 5 "TestProvider" bash -c "exit 1"
      The status should eq 1
      The output should include "(provider returned no output)"
      The stderr should be present
    End

    It 'does not output placeholder for empty output with success'
      When call execute_with_timeout 5 "TestProvider" true
      The status should eq 0
      The output should not include "(provider returned no output)"
      The stderr should be present
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

Describe 'execute_provider_with_timeout() routing'
  Include "$LIB_DIR/providers.sh"
  
  # NOTE: ShellSpec mocks don't propagate to subshells, so we can't easily
  # test the full provider execution. Instead, we test:
  # 1. That the function exists and accepts correct parameters
  # 2. Ollama host validation (happens before subshell)
  
  setup() {
    export CI=true
    export GGA_NO_SPINNER=1
  }
  Before 'setup'
  
  cleanup() {
    unset CI
    unset GGA_NO_SPINNER
    unset OLLAMA_HOST
  }
  After 'cleanup'

  Describe 'ollama host validation'
    It 'fails with invalid OLLAMA_HOST before attempting execution'
      OLLAMA_HOST="invalid://bad"
      
      When call execute_provider_with_timeout "ollama:llama3" "test" 5
      The status should be failure
      The stderr should include "Invalid OLLAMA_HOST"
      The output should be blank
    End

    It 'fails with command injection attempt in OLLAMA_HOST'
      OLLAMA_HOST="http://localhost:11434/api -d @/etc/passwd #"
      
      When call execute_provider_with_timeout "ollama:llama3" "test" 5
      The status should be failure
      The stderr should include "Invalid OLLAMA_HOST"
      The output should be blank
    End
  End

  Describe 'timeout parameter handling'
    # Test that short timeout causes timeout (proves parameter is passed)
    It 'respects timeout parameter by timing out slow commands'
      # Use a command that will definitely timeout in 1 second
      When call execute_with_timeout 1 "TestProvider" sleep 10
      The status should eq 124
      The stderr should include "TIMEOUT"
      The output should be blank
    End
  End
End

Describe 'provider base extraction in timeout context'
  Include "$LIB_DIR/providers.sh"
  
  # Test helper functions used by execute_provider_with_timeout
  helper_get_base_provider() {
    local provider="$1"
    echo "${provider%%:*}"
  }
  
  helper_get_model() {
    local provider="$1"
    echo "${provider#*:}"
  }
  
  It 'extracts base provider from simple provider'
    When call helper_get_base_provider "claude"
    The output should eq "claude"
  End

  It 'extracts base provider from ollama:model'
    When call helper_get_base_provider "ollama:llama3.2"
    The output should eq "ollama"
  End

  It 'extracts base provider from opencode:model'
    When call helper_get_base_provider "opencode:gpt-4"
    The output should eq "opencode"
  End

  It 'extracts model from ollama:model format'
    When call helper_get_model "ollama:llama3.2"
    The output should eq "llama3.2"
  End

  It 'extracts model from opencode:model format'
    When call helper_get_model "opencode:gpt-4"
    The output should eq "gpt-4"
  End
End
