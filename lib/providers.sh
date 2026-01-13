#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - Provider Functions
# ============================================================================
# Handles execution for different AI providers:
# - claude: Anthropic Claude Code CLI
# - gemini: Google Gemini CLI
# - github:<model> GitHub Models with specified model
# - codex: OpenAI Codex CLI
# - opencode: OpenCode CLI (optional :model)
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
    opencode)
      if ! command -v opencode &> /dev/null; then
        echo -e "${RED}❌ OpenCode CLI not found${NC}"
        echo ""
        echo "Install OpenCode CLI:"
        echo "  https://opencode.ai"
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
      echo "  - opencode"
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
    opencode)
      local model="${provider#*:}"
      if [[ "$model" == "$provider" ]]; then
        model=""
      fi
      execute_opencode "$model" "$prompt"
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
  # Redirect stderr to stdout to capture any error messages
  printf '%s' "$prompt" | claude --print 2>&1
  return "${PIPESTATUS[1]}"
}

execute_gemini() {
  local prompt="$1"
  
  # Gemini CLI requires prompt as argument or via -p flag
  # Using -p flag for explicit prompt passing
  # Note: In CI/non-interactive environments, --yolo may be needed for auto-approval
  gemini -p "$prompt" 2>&1
  return $?
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

  if ! gh auth status &>/dev/null; then
      echo -e "${RED}❌ Not authenticated with GitHub${NC}" >&2
      echo "" >&2
      echo "Run:" >&2
      echo "  gh auth login" >&2
      echo "" >&2
      return 1
  fi

  local token
  token="$(gh auth token 2>/dev/null)"

  if [[ -z "$token" ]]; then
      echo -e "${RED}❌ Unable to retrieve GitHub auth token${NC}" >&2
      return 1
  fi

  local json_payload
  json_payload=$(jq -n \
                  --arg model "$model" \
                  --arg prompt "$prompt" \
                  '{
                      model: $model,
                      messages: [
                          { role: "system", content: "You are Guardian Angel, a code reviewer." },
                          { role: "user", content: $prompt }
                      ],
                      temperature: 0.2
                  }')

  local response
  local curl_error_file
  curl_error_file="$(mktemp)"

  if ! response=$(curl -sS https://models.inference.ai.azure.com/chat/completions \
          -H "Authorization: Bearer $token" \
          -H "Content-Type: application/json" \
          -d "$json_payload" 2> "$curl_error_file"); then
      local curl_error_msg
      curl_error_msg="$(<"$curl_error_file")"
      rm -f "$curl_error_file"
      if [[ -n "$curl_error_msg" ]]; then
          echo -e "${RED}❌ GitHub Models request failed: $curl_error_msg${NC}" >&2
      else
          echo -e "${RED}❌ GitHub Models request failed${NC}" >&2
      fi
      return 1
  fi

  rm -f "$curl_error_file"
  if [[ -z "$response" ]]; then
      echo -e "${RED}❌ Empty response from GitHub Models${NC}" >&2
      return 1
  fi

  if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
      local err_msg
      err_msg=$(echo "$response" | jq -r '.error.message // "Unknown API error"')
      echo -e "${RED}❌ API Error: $err_msg${NC}" >&2
      return 1
  fi

  echo "$response" | jq -r '.choices[0].message.content'
}

execute_opencode() {
  local model="$1"
  local prompt="$2"
  
  # OpenCode CLI accepts prompt as positional argument
  # opencode run [message..] - message is a positional array
  if [[ -n "$model" ]]; then
    opencode run --model "$model" "$prompt" 2>&1
  else
    opencode run "$prompt" 2>&1
  fi
  return $?
}

execute_ollama() {
  local model="$1"
  local prompt="$2"
  local host="${OLLAMA_HOST:-http://localhost:11434}"
  
  # Validate OLLAMA_HOST format to prevent injection attacks
  if ! validate_ollama_host "$host"; then
    echo "Error: Invalid OLLAMA_HOST format. Expected: http(s)://hostname(:port)" >&2
    return 1
  fi
  
  # Use python3 + curl if available (cleaner output, supports remote hosts)
  # Falls back to CLI with ANSI stripping if python3 is not available
  if command -v python3 &> /dev/null && command -v curl &> /dev/null; then
    execute_ollama_api "$model" "$prompt" "$host"
    return $?
  else
    execute_ollama_cli "$model" "$prompt"
    return $?
  fi
}

# Validate OLLAMA_HOST to prevent command injection
# Accepts: http(s)://hostname(:port) with optional trailing slash
validate_ollama_host() {
  local host="$1"
  
  # Regex: http or https, followed by hostname (alphanumeric, dots, hyphens), 
  # optional port, optional trailing slash
  if [[ "$host" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?/?$ ]]; then
    return 0
  fi
  return 1
}

# Execute Ollama via REST API using curl + python3
# This approach produces clean output without terminal escape codes
execute_ollama_api() {
  local model="$1"
  local prompt="$2"
  local host="$3"
  
  # Build JSON payload safely using python3 to escape special characters
  # Using stdin to avoid ARG_MAX limits with large prompts
  local json_payload
  if ! json_payload=$(printf '%s' "$prompt" | python3 -c "
import sys, json
prompt = sys.stdin.read()
model = sys.argv[1]
payload = json.dumps({
    'model': model,
    'prompt': prompt,
    'stream': False
})
print(payload)
" "$model" 2>&1); then
    echo "Error: Failed to build JSON payload" >&2
    echo "$json_payload" >&2
    return 1
  fi
  
  # Remove trailing slash from host if present
  host="${host%/}"
  
  # Call Ollama API
  local api_response
  api_response=$(curl -s --fail-with-body \
    -H "Content-Type: application/json" \
    -d "$json_payload" \
    "${host}/api/generate" 2>&1)
  
  local curl_status=$?
  if [[ $curl_status -ne 0 ]]; then
    echo "Error: Failed to connect to Ollama at $host" >&2
    echo "$api_response" >&2
    return 1
  fi
  
  # Extract response safely using python3
  printf '%s' "$api_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    response = data.get('response', '')
    if response:
        print(response)
    else:
        error = data.get('error', 'Unknown error from Ollama')
        print(f'Error: {error}', file=sys.stderr)
        sys.exit(1)
except json.JSONDecodeError as e:
    print(f'Error: Invalid JSON response from Ollama: {e}', file=sys.stderr)
    sys.exit(1)
"
  return $?
}

# Execute Ollama via CLI (fallback when python3/curl not available)
# Strips ANSI escape codes from output to fix STATUS detection
execute_ollama_cli() {
  local model="$1"
  local prompt="$2"
  
  # Run ollama CLI, suppress stderr (spinner/progress), strip ANSI codes from stdout
  # The 2>/dev/null removes spinner and progress messages
  # The sed removes any remaining ANSI escape sequences
  ollama run "$model" "$prompt" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
  return "${PIPESTATUS[0]}"
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
    opencode)
      local model="${provider#*:}"
      if [[ "$model" == "$provider" ]]; then
        echo "OpenCode CLI"
      else
        echo "OpenCode CLI (model: $model)"
      fi
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
