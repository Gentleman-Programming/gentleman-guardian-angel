#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - Provider Functions
# ============================================================================
# Handles execution for different AI providers:
# - claude: Anthropic Claude Code CLI
# - gemini: Google Gemini CLI
# - codex: OpenAI Codex CLI
# - opencode: OpenCode CLI (optional :model)
# - ollama:<model>: Ollama with specified model
# - lmstudio[:model]: LM Studio (optional model)
# - github:<model>: GitHub Models (OpenAI-compatible API)
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
    lmstudio)
      # Check if curl is available for API calls
      if ! command -v curl &> /dev/null; then
        echo -e "${RED}❌ curl not found${NC}"
        echo ""
        echo "Install curl:"
        echo "  # Most systems have it pre-installed"
        echo "  # Ubuntu/Debian: sudo apt-get install curl"
        echo "  # macOS: brew install curl"
        echo ""
        return 1
      fi
      ;;
    github)
      # GitHub Models requires gh CLI for authentication
      if ! command -v gh &> /dev/null; then
        echo -e "${RED}❌ gh CLI not found${NC}"
        echo ""
        echo "Install GitHub CLI:"
        echo "  brew install gh"
        echo "  # or: https://cli.github.com"
        echo ""
        echo "Then authenticate:"
        echo "  gh auth login"
        echo ""
        return 1
      fi
      # GitHub Models requires curl for API calls
      if ! command -v curl &> /dev/null; then
        echo -e "${RED}❌ curl not found${NC}"
        echo ""
        echo "Install curl:"
        echo "  # Most systems have it pre-installed"
        echo "  # Ubuntu/Debian: sudo apt-get install curl"
        echo "  # macOS: brew install curl"
        echo ""
        return 1
      fi
      # Model is required for GitHub Models
      local model="${provider#*:}"
      if [[ "$model" == "$provider" || -z "$model" ]]; then
        echo -e "${RED}❌ GitHub Models requires a model${NC}"
        echo ""
        echo "Specify model in provider config:"
        echo "  PROVIDER=\"github:gpt-4o\""
        echo "  PROVIDER=\"github:gpt-4.1\""
        echo "  PROVIDER=\"github:deepseek-r1\""
        echo "  PROVIDER=\"github:grok-3\""
        echo ""
        echo "See available models at: https://github.com/marketplace/models"
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
      echo "  - lmstudio[:model]"
      echo "  - github:<model>"
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
    lmstudio)
      local model="${provider#*:}"
      if [[ "$model" == "$provider" ]]; then
        model=""
      fi
      execute_lmstudio "$model" "$prompt"
      ;;
    github)
      local model="${provider#*:}"
      execute_github_models "$model" "$prompt"
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

  if ! is_gemini_authenticated; then
    echo -e "${RED}Gemini CLI is not authenticated${NC}" >&2
    echo ""
    echo "Please log in to Gemini CLI first:"
    echo "  gemini login"
    echo ""
    echo "Or visit: https://gemini.google.com"
    return 1
  fi

  # Gemini CLI in headless mode
  # Using stdin to pass prompt (avoids ARG_MAX limits for large prompts)
  # --yolo flag auto-approves all tool calls (required for CI/non-interactive)
  # See: https://geminicli.com/docs/cli/headless/
  printf '%s' "$prompt" | gemini --yolo 2>&1
  return "${PIPESTATUS[1]}"
}

is_gemini_authenticated() {
  gemini whoami &>/dev/null
}

execute_codex() {
  local prompt="$1"
  
  # Codex uses exec subcommand for non-interactive mode
  # Using --output-last-message to get just the final response
  codex exec "$prompt" 2>&1
  return $?
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

execute_lmstudio() {
  local model="$1"
  local prompt="$2"
  local host="${LMSTUDIO_HOST:-http://localhost:1234/v1}"

  # Validate LMSTUDIO_HOST format
  if ! validate_lmstudio_host "$host"; then
    echo "Error: Invalid LMSTUDIO_HOST format. Expected: http(s)://hostname(:port)(/v1)" >&2
    return 1
  fi

  # Use python3 for clean JSON parsing if available, otherwise basic response extraction
  if command -v python3 &> /dev/null; then
    execute_lmstudio_api "$model" "$prompt" "$host"
    return $?
  else
    execute_lmstudio_api_fallback "$model" "$prompt" "$host"
    return $?
  fi
}

validate_lmstudio_host() {
  local host="$1"

  # Regex: http or https, followed by hostname (alphanumeric, dots, hyphens),
  # optional port, optional /v1 path
  if [[ "$host" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/v1)?$ ]]; then
    return 0
  fi
  return 1
}

execute_lmstudio_api() {
  local model="$1"
  local prompt="$2"
  local host="$3"

  # Default model if not specified
  if [[ -z "$model" ]]; then
    model="local-model"
  fi

  # Build JSON payload
  local json_payload
  if ! json_payload=$(python3 -c "
import sys, json
payload = json.dumps({
    'model': '$model',
    'messages': [{'role': 'user', 'content': sys.stdin.read()}],
    'temperature': 0.7,
    'stream': False
})
print(payload)
" <<< "$prompt" 2>&1); then
    echo "Error: Failed to build JSON payload" >&2
    echo "$json_payload" >&2
    return 1
  fi

  # Ensure host ends with /v1
  if [[ ! "$host" =~ /v1$ ]]; then
    host="${host}/v1"
  fi

  local endpoint="${host}/chat/completions"

  # Call LM Studio API
  local api_response
  api_response=$(curl -s --fail-with-body \
    -H "Content-Type: application/json" \
    -d "$json_payload" \
    "$endpoint" 2>&1)

  local curl_status=$?
  if [[ $curl_status -ne 0 ]]; then
    echo "Error: Failed to connect to LM Studio at $host" >&2
    echo "$api_response" >&2
    return 1
  fi

  # Extract response
  printf '%s' "$api_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    response = data.get('choices', [{}])[0].get('message', {}).get('content', '')
    if response:
        print(response)
    else:
        error = data.get('error', {}).get('message', 'Unknown error from LM Studio')
        print(f'Error: {error}', file=sys.stderr)
        sys.exit(1)
except json.JSONDecodeError as e:
    print(f'Error: Invalid JSON response from LM Studio: {e}', file=sys.stderr)
    sys.exit(1)
except (KeyError, IndexError, TypeError) as e:
    print(f'Error: Unexpected response format from LM Studio', file=sys.stderr)
    sys.exit(1)
"
  return $?
}

execute_lmstudio_api_fallback() {
  local model="$1"
  local prompt="$2"
  local host="$3"

  # Default model if not specified
  if [[ -z "$model" ]]; then
    model="local-model"
  fi

  # Build JSON payload manually (less safe, but works without python3)
  local json_payload
  json_payload="{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\""
  json_payload+="$(printf '%s' "$prompt" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | sed ':a;N;$!ba;s/\n/\\n/g')"
  json_payload+="\"}],\"temperature\":0.7,\"stream\":false}"

  # Ensure host ends with /v1
  if [[ ! "$host" =~ /v1$ ]]; then
    host="${host}/v1"
  fi

  local endpoint="${host}/chat/completions"

  # Call LM Studio API
  local api_response
  api_response=$(curl -s --fail-with-body \
    -H "Content-Type: application/json" \
    -d "$json_payload" \
    "$endpoint" 2>&1)

  local curl_status=$?
  if [[ $curl_status -ne 0 ]]; then
    echo "Error: Failed to connect to LM Studio at $host" >&2
    echo "$api_response" >&2
    return 1
  fi

  # Extract response using sed/grep
  printf '%s' "$api_response" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g; s/\\"/"/g'
  return $?
}

# ============================================================================
# GitHub Models Implementation
# ============================================================================

# GitHub Models API endpoint (OpenAI-compatible)
GITHUB_MODELS_ENDPOINT="https://models.inference.ai.azure.com/chat/completions"

execute_github_models() {
  local model="$1"
  local prompt="$2"

  # Get auth token from gh CLI
  local token
  if ! token=$(gh auth token 2>&1); then
    echo "Error: GitHub CLI authentication failed" >&2
    echo "Run 'gh auth login' to authenticate" >&2
    return 1
  fi

  # Build JSON payload safely using python3
  local json_payload
  if ! json_payload=$(printf '%s' "$prompt" | python3 -c "
import sys, json
prompt = sys.stdin.read()
model = sys.argv[1]
payload = json.dumps({
    'model': model,
    'messages': [
        {'role': 'system', 'content': 'You are a helpful code review assistant.'},
        {'role': 'user', 'content': prompt}
    ],
    'temperature': 0.2
})
print(payload)
" "$model" 2>&1); then
    echo "Error: Failed to build JSON payload" >&2
    echo "$json_payload" >&2
    return 1
  fi

  # Call GitHub Models API
  # Use -s (silent) without --fail-with-body so we always get the response body
  # The python3 parser handles error responses from the API
  local api_response
  api_response=$(curl -sS \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $token" \
    -d "$json_payload" \
    "$GITHUB_MODELS_ENDPOINT" 2>&1)

  local curl_status=$?
  if [[ $curl_status -ne 0 ]]; then
    echo "Error: Failed to connect to GitHub Models API" >&2
    echo "$api_response" >&2
    return 1
  fi

  # Extract response using python3
  printf '%s' "$api_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Check for error response
    if 'error' in data:
        error = data['error']
        if isinstance(error, dict):
            msg = error.get('message', 'Unknown error from GitHub Models')
        else:
            msg = str(error)
        print(f'Error: {msg}', file=sys.stderr)
        sys.exit(1)
    # Extract content from choices
    choices = data.get('choices', [])
    if not choices:
        print('Error: Unexpected response format from GitHub Models', file=sys.stderr)
        sys.exit(1)
    content = choices[0].get('message', {}).get('content', '')
    if content:
        print(content)
    else:
        print('Error: Empty response from GitHub Models', file=sys.stderr)
        sys.exit(1)
except json.JSONDecodeError as e:
    print(f'Error: Invalid JSON response from GitHub Models: {e}', file=sys.stderr)
    sys.exit(1)
except (KeyError, IndexError, TypeError) as e:
    print(f'Error: Unexpected response format from GitHub Models', file=sys.stderr)
    sys.exit(1)
"
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
    lmstudio)
      local model="${provider#*:}"
      if [[ "$model" == "$provider" || -z "$model" ]]; then
        echo "LM Studio"
      else
        echo "LM Studio (model: $model)"
      fi
      ;;
    github)
      local model="${provider#*:}"
      echo "GitHub Models (model: $model)"
      ;;
    *)
      echo "Unknown provider"
      ;;
  esac
}

# ============================================================================
# Timeout Wrapper with Progress Feedback
# ============================================================================

# Execute a command with timeout and progress feedback
# Usage: execute_with_timeout <timeout_seconds> <provider_name> <command...>
# Returns: 0 on success, 124 on timeout, other on command failure
execute_with_timeout() {
  local timeout_seconds="$1"
  local provider_name="$2"
  shift 2

  local output_file
  output_file=$(mktemp "${TMPDIR:-/tmp}/gga_timeout_out.XXXXXX")
  local exit_code_file
  exit_code_file=$(mktemp "${TMPDIR:-/tmp}/gga_timeout_ec.XXXXXX")

  # Determine if we can use fancy spinner (TTY mode)
  local use_spinner=false
  if [[ -t 2 ]] && [[ -z "${CI:-}" ]] && [[ -z "${GGA_NO_SPINNER:-}" ]]; then
    use_spinner=true
  fi

  # Show initial status
  if [[ "$use_spinner" == "true" ]]; then
    printf "  Waiting for %s (timeout: %ds, Ctrl+C to cancel)...\n" "$provider_name" "$timeout_seconds" >&2
  else
    echo "  Waiting for $provider_name response (timeout: ${timeout_seconds}s)..." >&2
  fi

  # Run command in background and capture output (stdout and stderr combined)
  (
    "$@" > "$output_file" 2>&1
    echo $? > "$exit_code_file"
  ) &
  local cmd_pid=$!

  # Spinner characters and timing
  local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local spin_idx=0
  local start_time=$SECONDS
  local last_print=0

  # Wait for command with timeout, showing progress
  while kill -0 "$cmd_pid" 2>/dev/null; do
    local elapsed=$((SECONDS - start_time))

    if [[ $elapsed -ge $timeout_seconds ]]; then
      # Timeout reached - kill the process tree
      kill -TERM "$cmd_pid" 2>/dev/null || true
      sleep 0.5
      kill -KILL "$cmd_pid" 2>/dev/null || true
      wait "$cmd_pid" 2>/dev/null || true

      # Clear spinner line if in TTY mode
      [[ "$use_spinner" == "true" ]] && printf "\r\033[K" >&2

      # Output timeout error
      echo "" >&2
      echo "TIMEOUT: Provider did not respond within ${timeout_seconds} seconds." >&2
      echo "" >&2
      echo "Possible causes:" >&2
      echo "  - Large number of files being reviewed" >&2
      echo "  - Slow network connection" >&2
      echo "  - Provider API issues or rate limiting" >&2
      echo "" >&2
      echo "Solutions:" >&2
      echo "  - Increase TIMEOUT in .gga config (current: ${timeout_seconds}s)" >&2
      echo "  - Review fewer files at once" >&2
      echo "  - Check provider status/logs" >&2

      rm -f "$output_file" "$exit_code_file"
      return 124
    fi

    # Update progress display
    if [[ "$use_spinner" == "true" ]]; then
      local char="${spin_chars:spin_idx:1}"
      spin_idx=$(( (spin_idx + 1) % ${#spin_chars} ))
      printf "\r\033[K  \033[0;36m%s\033[0m Waiting for %s (%ds)..." "$char" "$provider_name" "$elapsed" >&2
      sleep 0.1
    else
      # Non-TTY: print update every 30 seconds
      if [[ $elapsed -ge $((last_print + 30)) ]]; then
        echo "  ... still waiting (${elapsed}s elapsed)" >&2
        last_print=$elapsed
      fi
      sleep 1
    fi
  done

  # Command finished - get exit code
  wait "$cmd_pid" 2>/dev/null || true

  local exit_code
  if [[ -f "$exit_code_file" ]]; then
    exit_code=$(cat "$exit_code_file")
  else
    exit_code=1
  fi

  # Trace mode: show internal state
  if [[ -n "${GGA_TRACE:-}" ]]; then
    echo "[TRACE] exit_code=$exit_code" >&2
    echo "[TRACE] output_file=$output_file size=$(wc -c < "$output_file" 2>/dev/null || echo 0)" >&2
  fi

  # Output the result (stdout + stderr combined)
  if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
    cat "$output_file"
  elif [[ "${exit_code:-1}" -ne 0 ]]; then
    echo "(provider returned no output)"
  fi

  rm -f "$output_file" "$exit_code_file"
  return "${exit_code:-1}"
}

# ============================================================================
# Provider Execution with Timeout
# ============================================================================

# Execute provider with timeout and progress feedback
# Usage: execute_provider_with_timeout <provider> <prompt> <timeout>
execute_provider_with_timeout() {
  local provider="$1"
  local prompt="$2"
  local timeout="${3:-300}"
  local base_provider="${provider%%:*}"

  case "$base_provider" in
    claude)
      execute_with_timeout "$timeout" "Claude" bash -c "printf '%s' \"\$1\" | claude --print 2>&1" -- "$prompt"
      ;;
    gemini)
      execute_with_timeout "$timeout" "Gemini" gemini -p "$prompt"
      ;;
    codex)
      execute_with_timeout "$timeout" "Codex" codex exec "$prompt"
      ;;
    opencode)
      local model="${provider#*:}"
      if [[ "$model" == "$provider" ]]; then
        model=""
      fi
      if [[ -n "$model" ]]; then
        execute_with_timeout "$timeout" "OpenCode" opencode run --model "$model" "$prompt"
      else
        execute_with_timeout "$timeout" "OpenCode" opencode run "$prompt"
      fi
      ;;
    ollama)
      local model="${provider#*:}"
      local host="${OLLAMA_HOST:-http://localhost:11434}"

      if ! validate_ollama_host "$host"; then
        echo "Error: Invalid OLLAMA_HOST format. Expected: http(s)://hostname(:port)" >&2
        return 1
      fi

      execute_with_timeout "$timeout" "Ollama ($model)" execute_ollama "$model" "$prompt"
      ;;
    lmstudio)
      local model="${provider#*:}"
      if [[ "$model" == "$provider" ]]; then
        model=""
      fi
      local host="${LMSTUDIO_HOST:-http://localhost:1234/v1}"

      if ! validate_lmstudio_host "$host"; then
        echo "Error: Invalid LMSTUDIO_HOST format. Expected: http(s)://hostname(:port)(/v1)" >&2
        return 1
      fi

      execute_with_timeout "$timeout" "LM Studio" execute_lmstudio "$model" "$prompt"
      ;;
    *)
      # Generic fallback: wrap execute_provider with timeout
      # This ensures new providers added later still get timeout support
      execute_with_timeout "$timeout" "$base_provider" execute_provider "$provider" "$prompt"
      ;;
  esac
}
