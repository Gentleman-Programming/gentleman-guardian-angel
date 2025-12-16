#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - Provider Functions
# ============================================================================
# Handles execution for different AI providers:
# - claude: Anthropic Claude Code CLI
# - gemini: Google Gemini CLI
# - github:<model> Github Models with specified model
# - codex: OpenAI Codex CLI
# - ollama:<model>: Ollama with specified model
# ============================================================================

# Colors (in case sourced independently)
RED='\033[0;31m'
NC='\033[0m'

# ============================================================================
# Provider Validation
# ============================================================================

validate_provider() {
  local provider="$1"
  local base_provider="${provider%%:*}"

  case "$base_provider" in
    claude)
      if ! command -v claude &> /dev/null; then
        echo -e "${RED}❌ Claude CLI not found${NC}"
        echo ""
        echo "Install Claude Code CLI:"
        echo "  https://claude.ai/code"
        echo ""
        return 1
      fi
      ;;
    gemini)
      if ! command -v gemini &> /dev/null; then
        echo -e "${RED}❌ Gemini CLI not found${NC}"
        echo ""
        echo "Install Gemini CLI:"
        echo "  npm install -g @anthropic-ai/gemini-cli"
        echo "  # or"
        echo "  brew install gemini"
        echo ""
        return 1
      fi
      ;;
    codex)
      if ! command -v codex &> /dev/null; then
        echo -e "${RED}❌ Codex CLI not found${NC}"
        echo ""
        echo "Install OpenAI Codex CLI:"
        echo "  npm install -g @openai/codex"
        echo "  # or"
        echo "  brew install --cask codex"
        echo ""
        return 1
      fi
      ;;
    github)
      if ! command -v gh &>/dev/null; then
          echo -e "${RED}❌ GitHub CLI (gh) not found${NC}"
          echo ""
          echo "Install GitHub CLI:"
          echo "  https://cli.github.com/"
          echo ""
          return 1
      fi

      if ! gh auth status &>/dev/null; then
          echo -e "${RED}❌ Not authenticated with GitHub${NC}"
          echo ""
          echo "Run:"
          echo "  gh auth login"
          echo ""
          return 1
      fi

      local model="${provider#*:}"
      if [[ "$model" == "$provider" || -z "$model" ]]; then
          echo -e "${RED}❌ GitHub Models requires a model${NC}"
          echo ""
          echo "Specify model in provider config:"
          echo "  PROVIDER=\"github:gpt-4.1\""
          echo "  PROVIDER=\"github:phi-4\""
          echo ""
          return 1
      fi
      ;;
    ollama)
      if ! command -v ollama &> /dev/null; then
        echo -e "${RED}❌ Ollama not found${NC}"
        echo ""
        echo "Install Ollama:"
        echo "  https://ollama.ai/download"
        echo "  # or"
        echo "  brew install ollama"
        echo ""
        return 1
      fi
      # Check if model is specified
      local model="${provider#*:}"
      if [[ "$model" == "$provider" || -z "$model" ]]; then
        echo -e "${RED}❌ Ollama requires a model${NC}"
        echo ""
        echo "Specify model in provider config:"
        echo "  PROVIDER=\"ollama:llama3.2\""
        echo "  PROVIDER=\"ollama:codellama\""
        echo ""
        return 1
      fi
      ;;
    *)
      echo -e "${RED}❌ Unknown provider: $provider${NC}"
      echo ""
      echo "Supported providers:"
      echo "  - claude"
      echo "  - gemini"
      echo "  - codex"
      echo "  - ollama:<model>"
      echo ""
      return 1
      ;;
  esac

  return 0
}

# ============================================================================
# Provider Execution
# ============================================================================

execute_provider() {
  local provider="$1"
  local prompt="$2"
  local base_provider="${provider%%:*}"

  case "$base_provider" in
    claude)
      execute_claude "$prompt"
      ;;
    gemini)
      execute_gemini "$prompt"
      ;;
    codex)
      execute_codex "$prompt"
      ;;
    github)
      local model="${provider#*:}"
      execute_github_models "$model" "$prompt"
      ;;
    ollama)
      local model="${provider#*:}"
      execute_ollama "$model" "$prompt"
      ;;
  esac
}

# ============================================================================
# Individual Provider Implementations
# ============================================================================

execute_claude() {
  local prompt="$1"
  
  # Claude CLI accepts prompt via stdin pipe
  echo "$prompt" | claude --print 2>&1
  return "${PIPESTATUS[1]}"
}

execute_gemini() {
  local prompt="$1"
  
  # Gemini CLI accepts prompt via stdin pipe or -p flag
  echo "$prompt" | gemini 2>&1
  return "${PIPESTATUS[1]}"
}

execute_codex() {
  local prompt="$1"

  # Codex uses exec subcommand for non-interactive mode
  # Using --output-last-message to get just the final response
  codex exec "$prompt" 2>&1
  return $?
}

execute_github_models() {
  local model="$1"
  local prompt="$2"

  local token
  token="$(gh auth token 2>/dev/null)"

  if [[ -z "$token" ]]; then
      echo -e "${RED}❌ Unable to retrieve GitHub auth token${NC}"
      return 1
  fi

  local response
  response=$(
      curl -sS https://models.inference.ai.azure.com/chat/completions \
          -H "Authorization: Bearer $token" \
          -H "Content-Type: application/json" \
          -d "$(
              jq -n \
                  --arg model "$model" \
                  --arg prompt "$prompt" \
                  '{
              model: $model,
              messages: [
                  { role: "system", content: "You are Guardian Angel a code reviewer." },
                  { role: "user", content: $prompt }
              ],
              temperature: 0.2
          }'
          )"
  )

  if [[ $? -ne 0 || -z "$response" ]]; then
      echo -e "${RED}❌ GitHub Models request failed${NC}"
      return 1
  fi

  echo "$response" | jq -r '.choices[0].message.content'
}

execute_ollama() {
  local model="$1"
  local prompt="$2"

  # Ollama accepts prompt as argument after model name
  ollama run "$model" "$prompt" 2>&1
  return $?
}

# ============================================================================
# Provider Info
# ============================================================================

get_provider_info() {
  local provider="$1"
  local base_provider="${provider%%:*}"

  case "$base_provider" in
    claude)
      echo "Anthropic Claude Code CLI"
      ;;
    gemini)
      echo "Google Gemini CLI"
      ;;
    codex)
      echo "OpenAI Codex CLI"
      ;;
    github)
        local model="${provider#*:}"
        echo "GitHub Models (model: $model)"
        ;;
    ollama)
      local model="${provider#*:}"
      echo "Ollama (model: $model)"
      ;;
    *)
      echo "Unknown provider"
      ;;
  esac
}
