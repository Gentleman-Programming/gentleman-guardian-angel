# Configuration

> 📖 Back to [README](../README.md)

Complete reference for configuring Gentleman Guardian Angel.

---

## Config File: `.gga`

Create this file in your project root:

```bash
# AI Provider (required)
# Options: claude, gemini, codex, opencode, ollama:<model>, lmstudio[:model], github:<model>
PROVIDER="claude"

# Fallback chain (optional) — comma-separated, tried in order
# On transient failure (timeout, rate-limit, network), GGA advances to the next provider.
# On config error (missing API key, auth rejection), GGA aborts immediately.
PROVIDER="claude,gemini,ollama:llama3"

# File patterns to review (comma-separated globs)
# Default: * (all files)
FILE_PATTERNS="*.ts,*.tsx,*.js,*.jsx"

# Patterns to exclude from review (comma-separated globs)
# Default: none
EXCLUDE_PATTERNS="*.test.ts,*.spec.ts,*.d.ts"

# File containing your coding standards
# Default: AGENTS.md
RULES_FILE="AGENTS.md"

# Fail if AI response is ambiguous (recommended for CI)
# Default: true
STRICT_MODE="true"

# Timeout in seconds for AI provider response
# Default: 300 (5 minutes)
TIMEOUT="300"

# Base branch for --pr-mode (auto-detects main/master/develop if empty)
# PR_BASE_BRANCH="main"
```

---

## Configuration Options

| Option             | Required | Default     | Description                              |
| ------------------ | -------- | ----------- | ---------------------------------------- |
| `PROVIDER`         | ✅ Yes   | -           | AI provider to use (comma-separated for fallback chain) |
| `FILE_PATTERNS`    | No       | `*`         | Comma-separated file patterns to include |
| `EXCLUDE_PATTERNS` | No       | -           | Comma-separated file patterns to exclude |
| `RULES_FILE`       | No       | `AGENTS.md` | Path to your coding standards file       |
| `STRICT_MODE`      | No       | `true`      | Fail on ambiguous AI responses           |
| `TIMEOUT`          | No       | `300`       | Max seconds to wait for AI response      |
| `PR_BASE_BRANCH`   | No       | auto-detect | Base branch for `--pr-mode`              |

---

## Config Hierarchy (Priority Order)

1. **Environment variable** `GGA_PROVIDER`, `GGA_TIMEOUT` (highest priority)
2. **Project config** `.gga` (in project root)
3. **Global config** `~/.config/gga/config` (lowest priority)

---

## Environment Variable Overrides

```bash
# Override provider for a single run
GGA_PROVIDER="gemini" gga run

# Or export for the session
export GGA_PROVIDER="ollama:llama3.2"

# Override timeout for a single run
GGA_TIMEOUT=600 gga run
```
