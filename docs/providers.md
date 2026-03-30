# Providers

> 📖 Back to [README](../README.md)

Detailed setup and configuration for all supported AI providers.

---

## Providers Table

Use whichever AI CLI you have installed:

| Provider          | Config Value       | CLI Command Used                  | Installation                                                                       |
| ----------------- | ------------------ | --------------------------------- | ---------------------------------------------------------------------------------- |
| **Claude**        | `claude`           | `echo "prompt" \| claude --print` | [claude.ai/code](https://claude.ai/code)                                           |
| **Gemini**        | `gemini`           | `echo "prompt" \| gemini`         | [github.com/google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli) |
| **Codex**         | `codex`            | `codex exec "prompt"`             | `npm i -g @openai/codex`                                                           |
| **OpenCode**      | `opencode`         | `echo "prompt" \| opencode run`   | [opencode.ai](https://opencode.ai)                                                 |
| **Cursor Agent**  | `cursor[:model]`   | `agent -p "prompt" --output-format text` | [cursor.com](https://cursor.com)                                                   |
| **Ollama**        | `ollama:<model>`   | `ollama run <model> "prompt"`     | [ollama.ai](https://ollama.ai)                                                     |
| **LM Studio**     | `lmstudio[:model]` | HTTP API call to local server     | [lmstudio.ai](https://lmstudio.ai)                                                 |
| **GitHub Models** | `github:<model>`   | HTTP API via `gh auth token`      | [github.com/marketplace/models](https://github.com/marketplace/models)              |

---

## Provider Examples

```bash
# Use Claude (recommended - most reliable)
PROVIDER="claude"

# Use Google Gemini
PROVIDER="gemini"

# Use OpenAI Codex
PROVIDER="codex"

# Use OpenCode (uses default model)
PROVIDER="opencode"

# Use OpenCode with specific model
PROVIDER="opencode:anthropic/claude-opus-4-5"

# Use Cursor Agent (default model)
PROVIDER="cursor"

# Use Cursor Agent with specific model
PROVIDER="cursor:composer-2"

# Use Ollama with Llama 3.2
PROVIDER="ollama:llama3.2"

# Use Ollama with CodeLlama (optimized for code)
PROVIDER="ollama:codellama"

# Use Ollama with Qwen Coder
PROVIDER="ollama:qwen2.5-coder"

# Use Ollama with DeepSeek Coder
PROVIDER="ollama:deepseek-coder"

# Use LM Studio with default model
PROVIDER="lmstudio"

# Use LM Studio with specific model
PROVIDER="lmstudio:llama-3.2-3b-instruct"

# Use LM Studio with custom host
LMSTUDIO_HOST="http://localhost:8080/v1"
PROVIDER="lmstudio"

# Use GitHub Models (requires: gh auth login)
PROVIDER="github:gpt-4o"
PROVIDER="github:gpt-4.1"
PROVIDER="github:deepseek-r1"
PROVIDER="github:grok-3"

# Antigravity / VS Code users: use any provider CLI from your integrated terminal
# Antigravity comes with Gemini built-in — just set:
PROVIDER="gemini"
```

---

## Provider-Specific Notes

### Claude

Most reliable at following instructions. Recommended for strict mode and CI/CD pipelines.

```bash
# Install
# See https://claude.ai/code

# Test it works
echo "Say hello" | claude --print
```

### Gemini

Google's Gemini CLI. Built into Antigravity IDE.

```bash
# Install
# See https://github.com/google-gemini/gemini-cli

# Test it works
echo "Say hello" | gemini
```

### Cursor Agent

Uses Cursor's built-in Agent CLI to interact with the models via your Cursor account.

```bash
# Install Cursor Agent CLI
curl https://cursor.com/install -fsS | bash

# Test it works
agent -p "Say hello" --output-format text
```

### GitHub Models

Access dozens of models (GPT-4o, DeepSeek R1, Grok 3, Phi-4, LLaMA) using your GitHub account — no extra API keys.

```bash
# 1. Install GitHub CLI
brew install gh

# 2. Authenticate
gh auth login

# 3. Configure GGA
echo 'PROVIDER="github:gpt-4o"' > .gga

# Available models: https://github.com/marketplace/models
```

### Ollama (Local)

Run models locally. No API keys, full privacy.

```bash
# Install
# See https://ollama.ai

# Pull a model
ollama pull llama3.2
ollama pull codellama
ollama pull qwen2.5-coder

# Configure GGA
PROVIDER="ollama:llama3.2"

# Custom host (if not localhost:11434)
OLLAMA_HOST="http://192.168.1.100:11434"
PROVIDER="ollama:llama3.2"
```

> ⚠️ **Ollama limitation**: Ollama is a pure LLM without file-reading tools. If you use references in your AGENTS.md, consolidate them into a single file.

### LM Studio (Local)

Run models locally via LM Studio's OpenAI-compatible API.

```bash
# 1. Download and open LM Studio: https://lmstudio.ai
# 2. Download a model in LM Studio
# 3. Start the local server (Local Server tab)
# 4. Configure GGA
PROVIDER="lmstudio"                              # uses loaded model
PROVIDER="lmstudio:llama-3.2-3b-instruct"       # specific model

# Custom host/port
LMSTUDIO_HOST="http://localhost:8080/v1"
PROVIDER="lmstudio"

# Test the connection
curl http://localhost:1234/v1/models
```
