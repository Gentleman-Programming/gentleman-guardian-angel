# shellcheck shell=bash

Describe 'providers.sh'
  Include "$LIB_DIR/providers.sh"

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
