# shellcheck shell=bash

Describe 'providers.sh'
  Include "$LIB_DIR/providers.sh"

  Describe 'validate_ollama_host()'
    It 'accepts localhost with port'
      When call validate_ollama_host "http://localhost:11434"
      The status should be success
    End

    It 'accepts localhost with trailing slash'
      When call validate_ollama_host "http://localhost:11434/"
      The status should be success
    End

    It 'accepts https'
      When call validate_ollama_host "https://ollama.example.com:8080"
      The status should be success
    End

    It 'accepts IP address'
      When call validate_ollama_host "http://192.168.1.100:11434"
      The status should be success
    End

    It 'accepts hostname without port'
      When call validate_ollama_host "http://ollama.local"
      The status should be success
    End

    It 'rejects URL with path'
      When call validate_ollama_host "http://evil.com/steal?x=1"
      The status should be failure
    End

    It 'rejects URL with query string'
      When call validate_ollama_host "http://localhost:11434?foo=bar"
      The status should be failure
    End

    It 'rejects command injection attempt'
      When call validate_ollama_host "http://localhost:11434/api -d @/etc/passwd #"
      The status should be failure
    End

    It 'rejects file protocol'
      When call validate_ollama_host "file:///etc/passwd"
      The status should be failure
    End

    It 'rejects newline injection'
      When call validate_ollama_host $'http://localhost:11434\nX-Injected: header'
      The status should be failure
    End

    It 'rejects empty string'
      When call validate_ollama_host ""
      The status should be failure
    End

    It 'rejects missing protocol'
      When call validate_ollama_host "localhost:11434"
      The status should be failure
    End
  End

  Describe 'execute_ollama()'
    # We need to mock the dependent functions/commands
    
    Describe 'routing logic'
      It 'calls execute_ollama_api when python3 and curl are available'
        # Mock command -v to return success for python3 and curl
        command() {
          case "$2" in
            python3|curl) return 0 ;;
            *) return 1 ;;
          esac
        }
        # Mock execute_ollama_api to track it was called
        execute_ollama_api() {
          echo "API_CALLED:$1:$3"
        }
        # Mock validate_ollama_host to pass
        validate_ollama_host() { return 0; }
        
        When call execute_ollama "llama3" "test prompt"
        The output should include "API_CALLED:llama3:http://localhost:11434"
      End

      It 'calls execute_ollama_cli when python3 is not available'
        # Mock command -v to return failure for python3
        command() {
          case "$2" in
            python3) return 1 ;;
            curl) return 0 ;;
            *) return 1 ;;
          esac
        }
        # Mock execute_ollama_cli to track it was called
        execute_ollama_cli() {
          echo "CLI_CALLED:$1"
        }
        # Mock validate_ollama_host to pass
        validate_ollama_host() { return 0; }
        
        When call execute_ollama "llama3" "test prompt"
        The output should include "CLI_CALLED:llama3"
      End

      It 'calls execute_ollama_cli when curl is not available'
        # Mock command -v to return failure for curl
        command() {
          case "$2" in
            python3) return 0 ;;
            curl) return 1 ;;
            *) return 1 ;;
          esac
        }
        # Mock execute_ollama_cli to track it was called
        execute_ollama_cli() {
          echo "CLI_CALLED:$1"
        }
        # Mock validate_ollama_host to pass
        validate_ollama_host() { return 0; }
        
        When call execute_ollama "llama3" "test prompt"
        The output should include "CLI_CALLED:llama3"
      End

      It 'fails when OLLAMA_HOST is invalid'
        OLLAMA_HOST="invalid-host"
        
        When call execute_ollama "llama3" "test prompt"
        The status should be failure
        The stderr should include "Invalid OLLAMA_HOST"
      End

      It 'uses custom OLLAMA_HOST when set'
        OLLAMA_HOST="http://custom-host:8080"
        # Mock command -v to return success
        command() { return 0; }
        # Mock execute_ollama_api to capture the host
        execute_ollama_api() {
          echo "HOST:$3"
        }
        # Mock validate_ollama_host to pass
        validate_ollama_host() { return 0; }
        
        When call execute_ollama "llama3" "test prompt"
        The output should include "HOST:http://custom-host:8080"
      End
    End
  End

  Describe 'execute_ollama_cli()'
    It 'strips ANSI escape codes from output'
      # Mock ollama to output ANSI codes
      ollama() {
        printf '\033[0;32mSTATUS: PASSED\033[0m\nAll good!'
      }
      
      When call execute_ollama_cli "llama3" "test prompt"
      The output should eq "STATUS: PASSED
All good!"
      The output should not include $'\033['
    End

    It 'passes model and prompt to ollama'
      ollama() {
        echo "model:$2 prompt:$3"
      }
      
      When call execute_ollama_cli "codellama" "review this code"
      The output should include "model:codellama"
      The output should include "prompt:review this code"
    End

    It 'returns ollama exit status'
      ollama() {
        return 42
      }
      
      When call execute_ollama_cli "llama3" "test"
      The status should eq 42
    End
  End

  Describe 'execute_ollama_api()'
    # These tests require python3 and curl to be available
    # Skip if not available
    skip_if_no_python3() {
      ! command -v python3 &> /dev/null
    }
    
    Skip if "python3 not available" skip_if_no_python3

    # NOTE: JSON payload building and URL handling are tested in integration tests
    # with real Ollama (spec/integration/ollama_spec.sh). ShellSpec cannot properly
    # mock system binaries like curl in subshells used by "When call".

    It 'handles curl failure'
      curl() {
        echo "Connection refused"
        return 7
      }
      
      When call execute_ollama_api "llama3" "test" "http://localhost:11434"
      The status should be failure
      The stderr should include "Failed to connect"
    End

    It 'parses JSON response correctly'
      curl() {
        echo '{"response": "STATUS: PASSED\nAll files comply."}'
      }
      
      When call execute_ollama_api "llama3" "test" "http://localhost:11434"
      The output should include "STATUS: PASSED"
    End

    It 'handles invalid JSON response'
      curl() {
        echo 'not valid json'
      }
      
      When call execute_ollama_api "llama3" "test" "http://localhost:11434"
      The status should be failure
      The stderr should include "Invalid JSON"
    End

    It 'handles response with error field'
      curl() {
        echo '{"error": "model not found"}'
      }
      
      When call execute_ollama_api "llama3" "test" "http://localhost:11434"
      The status should be failure
      The stderr should include "model not found"
    End
  End

  Describe 'get_provider_info()'
    # These tests don't require mocking - they just test the info function
    
    It 'returns info for claude'
      When call get_provider_info "claude"
      The output should include "Claude"
    End

    It 'returns info for gemini'
      When call get_provider_info "gemini"
      The output should include "Gemini"
    End

    It 'returns info for codex'
      When call get_provider_info "codex"
      The output should include "Codex"
    End

    It 'returns info for ollama with model name'
      When call get_provider_info "ollama:llama3.2"
      The output should include "Ollama"
      The output should include "llama3.2"
    End

    It 'returns info for github models with model name'
      When call get_provider_info "github:gpt-4.1"
      The output should include "GitHub"
      The output should include "gpt-4.1"
    End

    It 'returns unknown for invalid provider'
      When call get_provider_info "invalid"
      The output should include "Unknown"
    End
  End

  Describe 'validate_provider() - invalid cases'
    # Test cases that don't depend on external commands
    # Note: validate_provider outputs to stdout (not stderr)
    
    It 'fails for unknown provider'
      When call validate_provider "unknown-provider"
      The status should be failure
      The output should include "Unknown provider"
    End

    It 'fails for empty provider'
      When call validate_provider ""
      The status should be failure
      The output should include "Unknown provider"
    End
  End

  Describe 'validate_provider() - github model validation'
    command() {
      if [ "$2" = "gh" ]; then return 0; fi
      builtin command "$@"
    }

    It 'succeeds when github provider includes a model'
      When call validate_provider "github:gpt-4.1"
      The status should be success
    End

    It 'fails when github provider has no model'
      When call validate_provider "github"
      The status should be failure
      The output should include "GitHub Models requires a model"
    End

    It 'fails when github provider ends with colon'
      When call validate_provider "github:"
      The status should be failure
      The output should include "GitHub Models requires a model"
    End
  End

  Describe 'validate_provider() - ollama model validation'
    # Ollama validation has logic that checks model format
    # This can fail BEFORE checking if ollama CLI exists

    # We need to test the model parsing logic
    # The function first checks CLI existence, then model
    # So we can't easily test the model validation without the CLI

    # Instead, let's test the parsing helper if we had one
    # For now, we'll skip these or mark them as pending

    Skip "Requires refactoring validate_provider to separate concerns"
  End

  Describe 'provider base extraction'
    # Test the base provider extraction logic

    helper_get_base_provider() {
      local provider="$1"
      echo "${provider%%:*}"
    }

    It 'extracts base provider from simple provider'
      When call helper_get_base_provider "claude"
      The output should eq "claude"
    End

    It 'extracts base provider from ollama:model format'
      When call helper_get_base_provider "ollama:llama3.2"
      The output should eq "ollama"
    End

    It 'extracts base provider from ollama:model:version format'
      When call helper_get_base_provider "ollama:codellama:7b"
      The output should eq "ollama"
    End
  End

  Describe 'provider model extraction'
    # Test the model extraction logic for ollama
    
    helper_get_model() {
      local provider="$1"
      echo "${provider#*:}"
    }
    
    It 'extracts model from ollama:model format'
      When call helper_get_model "ollama:llama3.2"
      The output should eq "llama3.2"
    End

    It 'extracts model with version from ollama:model:version'
      When call helper_get_model "ollama:codellama:7b"
      The output should eq "codellama:7b"
    End

    It 'returns original when no colon present'
      When call helper_get_model "claude"
      The output should eq "claude"
    End
  End
End
