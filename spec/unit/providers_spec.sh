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

  Describe 'validate_lmstudio_host()'
    It 'accepts localhost with default port'
      When call validate_lmstudio_host "http://localhost:1234/v1"
      The status should be success
    End

    It 'accepts localhost without /v1 path'
      When call validate_lmstudio_host "http://localhost:1234"
      The status should be success
    End

    It 'accepts localhost with custom port'
      When call validate_lmstudio_host "http://localhost:8080/v1"
      The status should be success
    End

    It 'accepts https'
      When call validate_lmstudio_host "https://lmstudio.example.com:443/v1"
      The status should be success
    End

    It 'accepts IP address'
      When call validate_lmstudio_host "http://192.168.1.100:1234/v1"
      The status should be success
    End

    It 'accepts hostname without port and /v1'
      When call validate_lmstudio_host "http://lmstudio.local/v1"
      The status should be success
    End

    It 'rejects URL with query string'
      When call validate_lmstudio_host "http://localhost:1234/v1?foo=bar"
      The status should be failure
    End

    It 'rejects URL with path beyond /v1'
      When call validate_lmstudio_host "http://localhost:1234/v1/chat"
      The status should be failure
    End

    It 'rejects command injection attempt'
      When call validate_lmstudio_host "http://localhost:1234/api -d @/etc/passwd #"
      The status should be failure
    End

    It 'rejects file protocol'
      When call validate_lmstudio_host "file:///etc/passwd"
      The status should be failure
    End

    It 'rejects newline injection'
      When call validate_lmstudio_host $'http://localhost:1234\nX-Injected: header'
      The status should be failure
    End

    It 'rejects empty string'
      When call validate_lmstudio_host ""
      The status should be failure
    End

    It 'rejects missing protocol'
      When call validate_lmstudio_host "localhost:1234"
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

    It 'sends JSON payload through stdin instead of argv'
      curl() {
        local args="$*"
        local payload
        payload=$(cat)
        [[ "$args" == *"--data-binary @-"* ]] || { echo "missing stdin payload flag" >&2; return 64; }
        for arg in "$@"; do
          [[ "$arg" != "-d" && "$arg" != "--data" && "$arg" != "--data-raw" ]] || { echo "payload passed through argv" >&2; return 64; }
        done
        [[ "$payload" == *"large review prompt"* ]] || { echo "missing prompt in stdin payload" >&2; return 64; }
        echo '{"response": "STATUS: PASSED"}'
      }

      When call execute_ollama_api "llama3" "large review prompt" "http://localhost:11434"
      The status should be success
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

    It 'returns info for lmstudio without model'
      When call get_provider_info "lmstudio"
      The output should include "LM Studio"
    End

    It 'returns info for lmstudio with model name'
      When call get_provider_info "lmstudio:llama-3.2-3b-instruct"
      The output should include "LM Studio"
      The output should include "llama-3.2-3b-instruct"
    End

    It 'returns unknown for invalid provider'
      When call get_provider_info "invalid"
      The output should include "Unknown"
    End
  End

  Describe 'execute_lmstudio()'
    Describe 'routing logic'
      It 'calls execute_lmstudio_api when python3 and curl are available'
        command() {
          case "$2" in
            python3|curl) return 0 ;;
            *) return 1 ;;
          esac
        }
        execute_lmstudio_api() {
          echo "API_CALLED:$1:$3"
        }
        validate_lmstudio_host() { return 0; }

        When call execute_lmstudio "" "test prompt"
        The output should include "API_CALLED::http://localhost:1234/v1"
      End

      It 'calls execute_lmstudio_api_fallback when python3 is not available'
        command() {
          case "$2" in
            python3) return 1 ;;
            curl) return 0 ;;
            *) return 1 ;;
          esac
        }
        execute_lmstudio_api_fallback() {
          echo "FALLBACK_CALLED:$1:$3"
        }
        validate_lmstudio_host() { return 0; }

        When call execute_lmstudio "llama-3" "test prompt"
        The output should include "FALLBACK_CALLED:llama-3:http://localhost:1234/v1"
      End

      It 'fails when LMSTUDIO_HOST is invalid'
        LMSTUDIO_HOST="invalid-host"

        When call execute_lmstudio "" "test prompt"
        The status should be failure
        The stderr should include "Invalid LMSTUDIO_HOST"
      End

      It 'uses custom LMSTUDIO_HOST when set'
        LMSTUDIO_HOST="http://custom-host:8080/v1"
        command() { return 0; }
        execute_lmstudio_api() {
          echo "HOST:$3"
        }
        validate_lmstudio_host() { return 0; }

        When call execute_lmstudio "llama-3" "test prompt"
        The output should include "HOST:http://custom-host:8080/v1"
      End

      It 'passes model to API function'
        command() { return 0; }
        execute_lmstudio_api() {
          echo "MODEL:$1"
        }
        validate_lmstudio_host() { return 0; }

        When call execute_lmstudio "llama-3.2" "test prompt"
        The output should include "MODEL:llama-3.2"
      End
    End
  End

  Describe 'execute_lmstudio_api()'
    skip_if_no_python3() {
      ! command -v python3 &> /dev/null
    }

    Skip if "python3 not available" skip_if_no_python3

    It 'handles curl failure'
      curl() {
        echo "Connection refused"
        return 7
      }

      When call execute_lmstudio_api "llama-3" "test" "http://localhost:1234/v1"
      The status should be failure
      The stderr should include "Failed to connect"
    End

    It 'parses JSON response correctly'
      curl() {
        cat <<'EOF'
{
  "choices": [
    {
      "message": {
        "content": "STATUS: PASSED\nAll files comply."
      }
    }
  ]
}
EOF
      }

      When call execute_lmstudio_api "llama-3" "test" "http://localhost:1234/v1"
      The output should include "STATUS: PASSED"
    End

    It 'sends JSON payload through stdin instead of argv'
      curl() {
        local args="$*"
        local payload
        payload=$(cat)
        [[ "$args" == *"--data-binary @-"* ]] || { echo "missing stdin payload flag" >&2; return 64; }
        for arg in "$@"; do
          [[ "$arg" != "-d" && "$arg" != "--data" && "$arg" != "--data-raw" ]] || { echo "payload passed through argv" >&2; return 64; }
        done
        [[ "$payload" == *"large review prompt"* ]] || { echo "missing prompt in stdin payload" >&2; return 64; }
        echo '{"choices":[{"message":{"content":"STATUS: PASSED"}}]}'
      }

      When call execute_lmstudio_api "llama-3" "large review prompt" "http://localhost:1234/v1"
      The status should be success
      The output should include "STATUS: PASSED"
    End

    It 'handles invalid JSON response'
      curl() {
        echo 'not valid json'
      }

      When call execute_lmstudio_api "llama-3" "test" "http://localhost:1234/v1"
      The status should be failure
      The stderr should include "Invalid JSON"
    End

    It 'handles response with error field'
      curl() {
        echo '{"error": {"message": "model not found"}}'
      }

      When call execute_lmstudio_api "llama-3" "test" "http://localhost:1234/v1"
      The status should be failure
      The stderr should include "model not found"
    End

    It 'handles empty choices array'
      curl() {
        echo '{"choices": []}'
      }

      When call execute_lmstudio_api "llama-3" "test" "http://localhost:1234/v1"
      The status should be failure
      The stderr should include "Unexpected response format"
    End

    It 'uses default model when none specified'
      curl() {
        cat <<'EOF'
{
  "choices": [
    {
      "message": {
        "content": "LOCAL_MODEL_RESPONSE"
      }
    }
  ]
}
EOF
      }

      When call execute_lmstudio_api "" "test" "http://localhost:1234/v1"
      The status should be success
      The output should eq "LOCAL_MODEL_RESPONSE"
    End
  End

  Describe 'execute_lmstudio_api_fallback()'
    It 'sends JSON payload through stdin instead of argv'
      curl() {
        local args="$*"
        local payload
        payload=$(cat)
        [[ "$args" == *"--data-binary @-"* ]] || { echo "missing stdin payload flag" >&2; return 64; }
        for arg in "$@"; do
          [[ "$arg" != "-d" && "$arg" != "--data" && "$arg" != "--data-raw" ]] || { echo "payload passed through argv" >&2; return 64; }
        done
        [[ "$payload" == *"large review prompt"* ]] || { echo "missing prompt in stdin payload" >&2; return 64; }
        echo '{"choices":[{"message":{"content":"STATUS: PASSED"}}]}'
      }

      When call execute_lmstudio_api_fallback "llama-3" "large review prompt" "http://localhost:1234/v1"
      The status should be success
      The output should include "STATUS: PASSED"
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

  Describe 'validate_provider() - lmstudio'
    # Test LM Studio validation - only requires curl, not LM Studio itself

    It 'fails when curl not available'
      # Mock command -v to fail for curl
      command() {
        case "$2" in
          curl) return 1 ;;
          *) return 1 ;;
        esac
      }

      When call validate_provider "lmstudio"
      The status should be failure
      The output should include "curl not found"
    End

    It 'succeeds when curl is available'
      # Mock command -v to succeed for curl
      command() {
        case "$2" in
          curl) return 0 ;;
          *) return 1 ;;
        esac
      }

      When call validate_provider "lmstudio"
      The status should be success
    End
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

  # ===========================================================================
  # Phase 1: parse_provider_list (REQ-FC-001)
  # ===========================================================================

  Describe 'parse_provider_list()'
    # parse_provider_list writes into an array passed by nameref; it does NOT
    # print to stdout. Assert the resulting array, not The output.

    It 'splits comma-separated list into ordered array'
      parse_provider_list "claude,gemini,ollama:llama3" _chain
      The value "${_chain[*]}" should eq "claude gemini ollama:llama3"
      The value "${#_chain[@]}" should eq 3
    End

    It 'preserves per-provider :model suffix'
      parse_provider_list "ollama:llama3" _chain
      The value "${_chain[*]}" should eq "ollama:llama3"
    End

    It 'ignores empty segments and trims whitespace'
      parse_provider_list "claude, ,gemini," _chain
      The value "${_chain[*]}" should eq "claude gemini"
    End

    It 'handles single provider (no comma)'
      parse_provider_list "claude" _chain
      The value "${_chain[*]}" should eq "claude"
    End

    It 'handles trailing comma gracefully'
      parse_provider_list "claude,gemini," _chain
      The value "${_chain[*]}" should eq "claude gemini"
    End

    It 'handles leading comma gracefully'
      parse_provider_list ",claude,gemini" _chain
      The value "${_chain[*]}" should eq "claude gemini"
    End
  End

  # ===========================================================================
  # Phase 1: classify_provider_error (REQ-FC-002 / REQ-FC-003)
  # ===========================================================================

  Describe 'classify_provider_error()'
    # --- TRANSIENT cases (REQ-FC-002) ---

    It 'classifies exit 124 (timeout) as TRANSIENT'
      When call classify_provider_error 124 ""
      The output should eq "TRANSIENT"
    End

    It 'classifies exit 126 (command invoked not executable) as TRANSIENT'
      When call classify_provider_error 126 ""
      The output should eq "TRANSIENT"
    End

    It 'classifies exit 127 (command not found) as TRANSIENT'
      When call classify_provider_error 127 ""
      The output should eq "TRANSIENT"
    End

    It 'classifies HTTP 429 (rate limit) as TRANSIENT'
      When call classify_provider_error 1 "HTTP 429 Too Many Requests"
      The output should eq "TRANSIENT"
    End

    It 'classifies HTTP 500 as TRANSIENT'
      When call classify_provider_error 1 "HTTP 500 Internal Server Error"
      The output should eq "TRANSIENT"
    End

    It 'classifies HTTP 502 as TRANSIENT'
      When call classify_provider_error 1 "HTTP 502 Bad Gateway"
      The output should eq "TRANSIENT"
    End

    It 'classifies HTTP 503 as TRANSIENT'
      When call classify_provider_error 1 "HTTP 503 Service Unavailable"
      The output should eq "TRANSIENT"
    End

    It 'classifies connection reset as TRANSIENT'
      When call classify_provider_error 1 "Connection reset by peer"
      The output should eq "TRANSIENT"
    End

    It 'classifies connection refused as TRANSIENT'
      When call classify_provider_error 1 "Connection refused"
      The output should eq "TRANSIENT"
    End

    It 'classifies timeout in output as TRANSIENT'
      When call classify_provider_error 1 "Request timed out"
      The output should eq "TRANSIENT"
    End

    It 'classifies rate limit text as TRANSIENT'
      When call classify_provider_error 1 "rate limit exceeded"
      The output should eq "TRANSIENT"
    End

    # --- CONFIG cases (REQ-FC-003) ---

    It 'classifies missing API key (empty env) as CONFIG'
      When call classify_provider_error 1 "API key not set"
      The output should eq "CONFIG"
    End

    It 'classifies MINIMAX_API_KEY as CONFIG'
      When call classify_provider_error 1 "MINIMAX_API_KEY not set"
      The output should eq "CONFIG"
    End

    It 'classifies HTTP 401 as CONFIG'
      When call classify_provider_error 1 "HTTP 401 Unauthorized"
      The output should eq "CONFIG"
    End

    It 'classifies HTTP 403 as CONFIG'
      When call classify_provider_error 1 "HTTP 403 Forbidden"
      The output should eq "CONFIG"
    End

    It 'classifies invalid model as CONFIG'
      When call classify_provider_error 1 "Invalid model name"
      The output should eq "CONFIG"
    End

    It 'classifies not authenticated as CONFIG'
      When call classify_provider_error 1 "not authenticated"
      The output should eq "CONFIG"
    End

    It 'classifies unknown provider as CONFIG'
      When call classify_provider_error 1 "Unknown provider"
      The output should eq "CONFIG"
    End

    It 'classifies requires a model as CONFIG'
      When call classify_provider_error 1 "requires a model"
      The output should eq "CONFIG"
    End

    # --- Precedence: CONFIG wins if both match ---

    It 'CONFIG pattern wins over TRANSIENT when both match'
      When call classify_provider_error 1 "HTTP 401 Unauthorized and rate limit exceeded"
      The output should eq "CONFIG"
    End

    # --- Unknown -> TRANSIENT ---

    It 'classifies unknown errors as TRANSIENT'
      When call classify_provider_error 1 "something completely unexpected"
      The output should eq "TRANSIENT"
    End

    It 'classifies zero exit with unknown output as TRANSIENT'
      When call classify_provider_error 0 "success but we check output"
      The output should eq "TRANSIENT"
    End
  End

  # ===========================================================================
  # Phase 2: execute_with_fallback (REQ-FC-004 / REQ-FC-005 / REQ-PD-001)
  # ===========================================================================

  Describe 'execute_with_fallback()'
    # ShellSpec runs `When call` and every $(...) substitution in a subshell,
    # so variable-based counters never survive. Mocks record calls on stderr
    # (which IS captured) and decide behavior by provider name instead.

    validate_provider() {
      echo "mock-validate: $1" >&2
      return 0
    }

    # Default success mock; individual It blocks override with their own.
    execute_provider_with_timeout() {
      echo "mock-execute: $1" >&2
      echo "STATUS: PASSED"
      return 0
    }

    classify_provider_error() {
      echo "TRANSIENT"
    }

    It 'stops on first success'
      declare -a GGA_CHAIN=(claude gemini ollama:llama3)

      When call execute_with_fallback "prompt" 300 GGA_CHAIN
      The output should eq "STATUS: PASSED"
      The status should be success
      The stderr should include "mock-execute: claude"
      The stderr should not include "mock-execute: gemini"
      The stderr should not include "mock-execute: ollama:llama3"
    End

    It 'advances on TRANSIENT failure'
      declare -a GGA_CHAIN=(claude gemini)
      execute_provider_with_timeout() {
        echo "mock-execute: $1" >&2
        case "$1" in
          claude) echo "timeout error"; return 124 ;;
          gemini) echo "STATUS: PASSED from gemini"; return 0 ;;
        esac
      }

      When call execute_with_fallback "prompt" 300 GGA_CHAIN
      The output should eq "STATUS: PASSED from gemini"
      The status should be success
      The stderr should include "mock-execute: claude"
      The stderr should include "mock-execute: gemini"
      The stderr should include "trying"
    End

    It 'returns failure when all providers TRANSIENT-fail'
      declare -a GGA_CHAIN=(claude gemini)
      execute_provider_with_timeout() {
        echo "mock-execute: $1" >&2
        echo "error from $1"
        return 124
      }

      When call execute_with_fallback "prompt" 300 GGA_CHAIN
      The status should be failure
      The output should include "error from gemini"
      The stderr should include "mock-execute: claude"
      The stderr should include "mock-execute: gemini"
      The stderr should include "trying 'none'"
    End

    It 'hard-aborts on CONFIG error without trying next'
      declare -a GGA_CHAIN=(claude gemini)
      classify_provider_error() {
        echo "CONFIG"
      }
      execute_provider_with_timeout() {
        echo "mock-execute: $1" >&2
        echo "HTTP 403 Forbidden"
        return 1
      }

      When call execute_with_fallback "prompt" 300 GGA_CHAIN
      The status should be failure
      The output should include "HTTP 403 Forbidden"
      The stderr should include "config error"
      The stderr should not include "mock-execute: gemini"
    End

    It 'validates each provider before executing'
      declare -a GGA_CHAIN=(claude gemini)

      When call execute_with_fallback "prompt" 300 GGA_CHAIN
      The status should be success
      The output should eq "STATUS: PASSED"
      The stderr should include "mock-validate: claude"
      The stderr should not include "mock-validate: gemini"
    End

    It 'advances when provider CLI is missing (validate returns 127)'
      declare -a GGA_CHAIN=(claude gemini)
      validate_provider() {
        echo "mock-validate: $1" >&2
        case "$1" in
          claude) return 127 ;;
          gemini) return 0 ;;
        esac
      }
      execute_provider_with_timeout() {
        echo "mock-execute: $1" >&2
        echo "STATUS: PASSED from gemini"
        return 0
      }

      When call execute_with_fallback "prompt" 300 GGA_CHAIN
      The output should eq "STATUS: PASSED from gemini"
      The status should be success
      The stderr should include "mock-validate: claude"
      The stderr should include "CLI not found"
      The stderr should include "mock-execute: gemini"
      The stderr should not include "mock-execute: claude"
    End

    It 'aborts on validation CONFIG failure without executing or advancing'
      declare -a GGA_CHAIN=(claude gemini)
      validate_provider() {
        echo "mock-validate: $1" >&2
        return 1
      }
      execute_provider_with_timeout() {
        echo "mock-execute: $1" >&2
        echo "STATUS: PASSED"
        return 0
      }

      When call execute_with_fallback "prompt" 300 GGA_CHAIN
      The status should be failure
      The stderr should include "mock-validate: claude"
      The stderr should include "CONFIG"
      The stderr should not include "mock-execute: claude"
      The stderr should not include "mock-execute: gemini"
    End

    It 'handles single-provider chain (passthrough)'
      declare -a GGA_CHAIN=(claude)

      When call execute_with_fallback "prompt" 300 GGA_CHAIN
      The output should eq "STATUS: PASSED"
      The status should be success
      The stderr should include "mock-execute: claude"
    End

    It 'logs transient fallback message to stderr'
      declare -a GGA_CHAIN=(claude gemini)
      execute_provider_with_timeout() {
        echo "mock-execute: $1" >&2
        case "$1" in
          claude) echo "timeout"; return 124 ;;
          gemini) echo "STATUS: PASSED"; return 0 ;;
        esac
      }

      When call execute_with_fallback "prompt" 300 GGA_CHAIN
      The status should be success
      The output should eq "STATUS: PASSED"
      The stderr should include "claude"
      The stderr should include "trying"
    End
  End

  # ===========================================================================
  # Phase 2 Task 2.3: ollama without model CONFIG hard-abort
  # ===========================================================================

  Describe 'validate_provider() - ollama without model'
    It 'fails for ollama without model (CONFIG hard-abort)'
      # validate_provider checks ollama CLI first, then model
      # Without ollama CLI, it returns error for CLI not found
      # With ollama mocked, it should fail on missing model
      command() {
        case "$2" in
          ollama) return 0 ;;
          *) return 1 ;;
        esac
      }

      When call validate_provider "ollama"
      The status should be failure
      The output should include "requires a model"
    End
  End
End
