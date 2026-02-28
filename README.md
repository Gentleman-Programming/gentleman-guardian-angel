<p align="center">
  <img width="1024" height="408" alt="image" src="https://github.com/user-attachments/assets/e534ba1e-0044-45c7-a788-b455733c0052" />
</p>

<p align="center">
  <strong>Provider-agnostic code review using AI</strong><br>
  Use Claude, Gemini, Codex, OpenCode, Antigravity, Ollama, LM Studio, GitHub Models, or any AI to enforce your coding standards.<br>
  Zero dependencies. Pure Bash. Works everywhere.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-2.7.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License">
  <img src="https://img.shields.io/badge/bash-5.0%2B-orange.svg" alt="Bash">
  <img src="https://img.shields.io/badge/homebrew-tap-FBB040.svg" alt="Homebrew">
  <img src="https://img.shields.io/badge/tests-174%20passing-brightgreen.svg" alt="Tests">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs Welcome">
</p>

<p align="center">
  <a href="#-installation">Installation</a> •
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-providers">Providers</a> •
  <a href="#-commands">Commands</a> •
  <a href="#-configuration">Configuration</a> •
  <a href="#-smart-caching">Caching</a> •
  <a href="#-development">Development</a>
</p>

---

## Example

<img width="962" height="941" alt="image" src="https://github.com/user-attachments/assets/c8963dff-6aa5-420c-b58b-1416e81af384" />

## 🎯 Why?

You have coding standards. Your team ignores them. Code reviews catch issues too late.

**Gentleman Guardian Angel** runs on every commit, validating your staged files against your project's `AGENTS.md` (or any rules file). It's like having a senior developer review every line before it hits the repo.

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐
│   git commit    │ ──▶ │  AI Review   │ ──▶ │  ✅ Pass/Fail   │
│  (staged files) │     │  (any LLM)   │     │  (with details) │
└─────────────────┘     └──────────────┘     └─────────────────┘
```

**Key features:**

- 🔌 **Provider agnostic** - Use whatever AI you have installed
- 📦 **Zero dependencies** - Pure Bash, no Node/Python/Go required
- 🪝 **Git native** - Installs as a standard pre-commit hook
- ⚙️ **Highly configurable** - File patterns, exclusions, custom rules
- 🚨 **Strict mode** - Fail CI on ambiguous responses
- ⚡ **Smart caching** - Skip unchanged files for faster reviews
- ⏱️ **Timeout & progress** - Configurable timeout with visual spinner
- 🔍 **PR review mode** - Review full PRs, not just last commit
- 🍺 **Homebrew ready** - One command install

---

## 📦 Installation

### Homebrew (Recommended) 🍺

```bash
brew tap gentleman-programming/tap
brew install gga
```

Or in a single command:

```bash
brew install gentleman-programming/tap/gga
```

### Manual Installation

```bash
git clone https://github.com/Gentleman-Programming/gentleman-guardian-angel.git
cd gga
./install.sh
```

### Verify Installation

```bash
gga version
# Output: gga v2.7.0
```

---

## 🚀 Quick Start

```bash
# 1. Go to your project
cd ~/your-project

# 2. Initialize config
gga init

# 3. Create your rules file
touch AGENTS.md  # Add your coding standards

# 4. Install the git hook
gga install

# 5. Done! Now every commit gets reviewed 🎉
```

---

## 🎬 Real World Example

Let's walk through a complete example from setup to commit:

### Step 1: Setup in your project

```bash
$ cd ~/projects/my-react-app

$ gga init

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Gentleman Guardian Angel v2.2.0
  Provider-agnostic code review using AI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Created config file: .gga

ℹ️  Next steps:
  1. Edit .gga to set your preferred provider
  2. Create AGENTS.md with your coding standards
  3. Run: gga install
```

### Step 2: Configure your provider

```bash
$ cat .gga

# AI Provider (required)
PROVIDER="claude"

# File patterns to include in review (comma-separated)
FILE_PATTERNS="*.ts,*.tsx,*.js,*.jsx"

# File patterns to exclude from review (comma-separated)
EXCLUDE_PATTERNS="*.test.ts,*.spec.ts,*.test.tsx,*.spec.tsx,*.d.ts"

# File containing code review rules
RULES_FILE="AGENTS.md"

# Strict mode: fail if AI response is ambiguous
STRICT_MODE="true"
```

### Step 3: Create your coding standards

```bash
$ cat > AGENTS.md << 'EOF'
# Code Review Rules

## TypeScript
- No `any` types - use proper typing
- Use `const` over `let` when possible
- Prefer interfaces over type aliases for objects

## React
- Use functional components with hooks
- No `import * as React` - use named imports like `import { useState }`
- All images must have alt text for accessibility

## Styling
- Use Tailwind CSS utilities only
- No inline styles or CSS-in-JS
- No hardcoded colors - use design system tokens
EOF
```

### Step 4: Install the git hook

```bash
$ gga install

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Gentleman Guardian Angel v2.2.0
  Provider-agnostic code review using AI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Installed pre-commit hook: /Users/dev/projects/my-react-app/.git/hooks/pre-commit
```

### Step 5: Make some changes and commit

```bash
$ git add src/components/Button.tsx
$ git commit -m "feat: add new button component"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Gentleman Guardian Angel v2.2.0
  Provider-agnostic code review using AI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ℹ️  Provider: claude
ℹ️  Rules file: AGENTS.md
ℹ️  File patterns: *.ts,*.tsx,*.js,*.jsx
ℹ️  Cache: enabled

Files to review:
  - src/components/Button.tsx

ℹ️  Sending to claude for review...

STATUS: FAILED

Violations found:

1. **src/components/Button.tsx:3** - TypeScript Rule
   - Issue: Using `any` type for props
   - Fix: Define proper interface for ButtonProps

2. **src/components/Button.tsx:15** - React Rule
   - Issue: Using `import * as React`
   - Fix: Use `import { useState, useCallback } from 'react'`

3. **src/components/Button.tsx:22** - Styling Rule
   - Issue: Hardcoded color `#3b82f6`
   - Fix: Use Tailwind class `bg-blue-500` instead

❌ CODE REVIEW FAILED

Fix the violations listed above before committing.
```

### Step 6: Fix issues and commit again

```bash
$ git add src/components/Button.tsx
$ git commit -m "feat: add new button component"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Gentleman Guardian Angel v2.2.0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ℹ️  Provider: claude
ℹ️  Cache: enabled

Files to review:
  - src/components/Button.tsx

ℹ️  Sending to claude for review...

STATUS: PASSED

All files comply with the coding standards defined in AGENTS.md.

✅ CODE REVIEW PASSED

[main 4a2b3c1] feat: add new button component
 1 file changed, 45 insertions(+)
 create mode 100644 src/components/Button.tsx
```

---

## 📋 Commands

| Command                | Description                                          | Example                    |
| ---------------------- | ---------------------------------------------------- | -------------------------- |
| `init`                 | Create sample `.gga` config file                     | `gga init`                 |
| `install`              | Install git pre-commit hook (default)                | `gga install`              |
| `install --commit-msg` | Install git commit-msg hook (for commit message validation) | `gga install --commit-msg` |
| `uninstall`            | Remove git hooks from current repo                   | `gga uninstall`            |
| `run`                  | Run code review on staged files                      | `gga run`                  |
| `run --ci`             | Run code review on last commit (for CI/CD)           | `gga run --ci`             |
| `run --pr-mode`        | Review all files changed in the full PR              | `gga run --pr-mode`        |
| `run --pr-mode --diff-only` | PR review with diffs only (faster, cheaper)     | `gga run --pr-mode --diff-only` |
| `run --no-cache`       | Run review ignoring cache                            | `gga run --no-cache`       |
| `config`               | Display current configuration and status             | `gga config`               |
| `cache status`         | Show cache status for current project                | `gga cache status`         |
| `cache clear`          | Clear cache for current project                      | `gga cache clear`          |
| `cache clear-all`      | Clear all cached data                                | `gga cache clear-all`      |
| `help`                 | Show help message with all commands                  | `gga help`                 |
| `version`              | Show installed version                               | `gga version`              |

### Command Details

#### `gga init`

Creates a sample `.gga` configuration file in your project root with sensible defaults.

```bash
$ gga init
✅ Created config file: .gga
```

#### `gga install`

Installs a git hook that automatically runs code review on every commit.

**Default (pre-commit hook):**

```bash
$ gga install
✅ Installed pre-commit hook: .git/hooks/pre-commit
```

**With commit message validation (commit-msg hook):**

```bash
$ gga install --commit-msg
✅ Installed commit-msg hook: .git/hooks/commit-msg
```

The `--commit-msg` flag installs a commit-msg hook instead of pre-commit. This allows GGA to also validate your commit message (e.g., conventional commits format, issue references, etc.). The commit message is automatically included in the AI review.

If a hook already exists, GGA will append to it rather than replacing it.

#### `gga uninstall`

Removes the git pre-commit hook from your repository.

```bash
$ gga uninstall
✅ Removed pre-commit hook
```

#### `gga run [--no-cache]`

Runs code review on currently staged files. Uses intelligent caching by default to skip unchanged files.

```bash
$ git add src/components/Button.tsx
$ gga run
# Reviews the staged file (uses cache)

$ gga run --no-cache
# Forces review of all files, ignoring cache
```

#### `gga config`

Shows the current configuration, including where config files are loaded from and all settings.

```bash
$ gga config

Current Configuration:

Config Files:
  Global:  Not found
  Project: .gga

Values:
  PROVIDER:          claude
  FILE_PATTERNS:     *.ts,*.tsx,*.js,*.jsx
  EXCLUDE_PATTERNS:  *.test.ts,*.spec.ts
  RULES_FILE:        AGENTS.md
  STRICT_MODE:       true
  TIMEOUT:           300s
  PR_BASE_BRANCH:    auto-detect

Rules File: Found
```

---

## ⚡ Smart Caching

GGA includes intelligent caching to speed up reviews by skipping files that haven't changed.

### How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                        Cache Logic                               │
├─────────────────────────────────────────────────────────────────┤
│  1. Hash AGENTS.md + .gga config                                │
│     └─► If changed → Invalidate ALL cache                       │
│                                                                  │
│  2. For each staged file:                                        │
│     └─► Hash file content                                        │
│         └─► If hash exists in cache with PASSED → Skip          │
│         └─► If not cached → Send to AI for review               │
│                                                                  │
│  3. After PASSED review:                                         │
│     └─► Store file hash in cache                                │
└─────────────────────────────────────────────────────────────────┘
```

### Cache Invalidation

The cache automatically invalidates when:

| Change                | Effect                        |
| --------------------- | ----------------------------- |
| File content changes  | Only that file is re-reviewed |
| `AGENTS.md` changes   | **All files** are re-reviewed |
| `.gga` config changes | **All files** are re-reviewed |

### Cache Commands

```bash
# Check cache status
$ gga cache status

Cache Status:

  Cache directory: ~/.cache/gga/a1b2c3d4...
  Cache validity: Valid
  Cached files: 12
  Cache size: 4.0K

# Clear project cache
$ gga cache clear
✅ Cleared cache for current project

# Clear all cache (all projects)
$ gga cache clear-all
✅ Cleared all cache data
```

### Bypass Cache

```bash
# Force review all files, ignoring cache
gga run --no-cache
```

### Cache Location

```
~/.cache/gga/
├── <project-hash-1>/
│   ├── metadata          # Hash of AGENTS.md + .gga
│   └── files/
│       ├── <file-hash-a> # "PASSED"
│       └── <file-hash-b> # "PASSED"
└── <project-hash-2>/
    └── ...
```

---

## 🔌 Providers

Use whichever AI CLI you have installed:

| Provider          | Config Value       | CLI Command Used                  | Installation                                                                       |
| ----------------- | ------------------ | --------------------------------- | ---------------------------------------------------------------------------------- |
| **Claude**        | `claude`           | `echo "prompt" \| claude --print` | [claude.ai/code](https://claude.ai/code)                                           |
| **Gemini**        | `gemini`           | `echo "prompt" \| gemini`         | [github.com/google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli) |
| **Codex**         | `codex`            | `codex exec "prompt"`             | `npm i -g @openai/codex`                                                           |
| **OpenCode**      | `opencode`         | `echo "prompt" \| opencode run`   | [opencode.ai](https://opencode.ai)                                                 |
| **Ollama**        | `ollama:<model>`   | `ollama run <model> "prompt"`     | [ollama.ai](https://ollama.ai)                                                     |
| **LM Studio**     | `lmstudio[:model]` | HTTP API call to local server     | [lmstudio.ai](https://lmstudio.ai)                                                 |
| **GitHub Models** | `github:<model>`   | HTTP API via `gh auth token`      | [github.com/marketplace/models](https://github.com/marketplace/models)              |

### Provider Examples

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

## ⚙️ Configuration

### Config File: `.gga`

Create this file in your project root:

```bash
# AI Provider (required)
# Options: claude, gemini, codex, opencode, ollama:<model>, lmstudio[:model], github:<model>
PROVIDER="claude"

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

### Configuration Options

| Option             | Required | Default     | Description                              |
| ------------------ | -------- | ----------- | ---------------------------------------- |
| `PROVIDER`         | ✅ Yes   | -           | AI provider to use                       |
| `FILE_PATTERNS`    | No       | `*`         | Comma-separated file patterns to include |
| `EXCLUDE_PATTERNS` | No       | -           | Comma-separated file patterns to exclude |
| `RULES_FILE`       | No       | `AGENTS.md` | Path to your coding standards file       |
| `STRICT_MODE`      | No       | `true`      | Fail on ambiguous AI responses           |
| `TIMEOUT`          | No       | `300`       | Max seconds to wait for AI response      |
| `PR_BASE_BRANCH`   | No       | auto-detect | Base branch for `--pr-mode`              |

### Config Hierarchy (Priority Order)

1. **Environment variable** `GGA_PROVIDER`, `GGA_TIMEOUT` (highest priority)
2. **Project config** `.gga` (in project root)
3. **Global config** `~/.config/gga/config` (lowest priority)

```bash
# Override provider for a single run
GGA_PROVIDER="gemini" gga run

# Or export for the session
export GGA_PROVIDER="ollama:llama3.2"

# Override timeout for a single run
GGA_TIMEOUT=600 gga run
```

---

## 📝 Rules File (AGENTS.md)

The AI needs to know your standards. Create an `AGENTS.md` file.

### Best Practices for AGENTS.md

Your rules file should be **optimized for LLM parsing**, not for human documentation. Here's why and how:

#### 1. Keep it Concise (~100-200 lines)

Large files dilute the AI's focus. A focused, concise file produces better reviews.

```markdown
# ❌ Bad: Verbose explanations

## TypeScript Guidelines

When writing TypeScript code, it's important to consider type safety.
The `any` type should be avoided because it defeats the purpose of
using TypeScript in the first place. Instead, you should always...
(continues for 50 more lines)

# ✅ Good: Direct and actionable

## TypeScript

REJECT if:

- `any` type used
- Missing return types on public functions
- Type assertions without justification
```

#### 2. Use Clear Action Keywords

Use `REJECT`, `REQUIRE`, `PREFER` to give the AI clear signals:

| Keyword     | Meaning              | AI Action                           |
| ----------- | -------------------- | ----------------------------------- |
| `REJECT if` | Hard rule, must fail | Returns `STATUS: FAILED`            |
| `REQUIRE`   | Mandatory pattern    | Returns `STATUS: FAILED` if missing |
| `PREFER`    | Soft recommendation  | May note but won't fail             |

#### 3. Use References for Complex Projects

For large projects or monorepos, use **references** instead of concatenating multiple files:

```markdown
# Code Review Rules

## References

- UI guidelines: `ui/AGENTS.md`
- API guidelines: `api/AGENTS.md`
- Shared rules: `docs/CODE-STYLE.md`

---

## Critical Rules (ALL files)

REJECT if:

- Hardcoded secrets/credentials
- `console.log` in production code
- Missing error handling
```

**Why references work:** Claude, Gemini, and Codex have built-in tools to read files. When they see a reference like "`ui/AGENTS.md`", they can go read it if they need more context. This keeps your main file focused while allowing deep dives when needed.

> ⚠️ **Note for Ollama users**: Ollama is a pure LLM without file-reading tools. If you use Ollama and need multiple rules files, you'll need to manually consolidate them into one file.

#### 4. Structure for Scanning

Use bullet points, not paragraphs. The AI scans faster:

```markdown
# ✅ Good: Scannable structure

## TypeScript/React

REJECT if:

- `import * as React` → use `import { useState }`
- Union types `type X = "a" | "b"` → use `const X = {...} as const`
- `any` type without `// @ts-expect-error` justification

PREFER:

- Named exports over default exports
- Composition over inheritance
```

#### 5. Real-World Example

Here's a battle-tested example from a production monorepo:

```markdown
# Code Review Rules

## References

- UI details: `ui/AGENTS.md`
- SDK details: `sdk/AGENTS.md`

---

## ALL FILES

REJECT if:

- Hardcoded secrets/credentials
- `any` type (TypeScript) or missing type hints (Python)
- Code duplication (violates DRY)
- Silent error handling (empty catch blocks)

---

## TypeScript/React

REJECT if:

- `import React` → use `import { useState }`
- `var()` or hex colors in className → use Tailwind
- `useMemo`/`useCallback` without justification (React 19 Compiler handles this)
- Missing `"use client"` in client components

PREFER:

- `cn()` for conditional class merging
- Semantic HTML over divs
- Colocated files (component + test + styles)

---

## Python

REJECT if:

- Missing type hints on public functions
- Bare `except:` without specific exception
- `print()` instead of `logger`

REQUIRE:

- Docstrings on all public classes/methods

---

## Response Format

FIRST LINE must be exactly:
STATUS: PASSED
or
STATUS: FAILED

If FAILED, list: `file:line - rule violated - issue`
```

This file is **89 lines**, uses clear keywords, and has references for component-specific rules.

> 💡 **Pro tip**: Your `AGENTS.md` can also serve as documentation for human reviewers!

---

## 🎨 Project Examples

### TypeScript/React Project

```bash
# .gga
PROVIDER="claude"
FILE_PATTERNS="*.ts,*.tsx"
EXCLUDE_PATTERNS="*.test.ts,*.test.tsx,*.spec.ts,*.d.ts,*.stories.tsx"
RULES_FILE="AGENTS.md"
```

### Python Project

```bash
# .gga
PROVIDER="lmstudio:codellama"
FILE_PATTERNS="*.py"
EXCLUDE_PATTERNS="*_test.py,test_*.py,conftest.py,__pycache__/*"
RULES_FILE=".coding-standards.md"
```

### Go Project

```bash
# .gga
PROVIDER="gemini"
FILE_PATTERNS="*.go"
EXCLUDE_PATTERNS="*_test.go,mock_*.go,*_mock.go"
```

### Full-Stack Monorepo

```bash
# .gga
PROVIDER="claude"
FILE_PATTERNS="*.ts,*.tsx,*.py,*.go"
EXCLUDE_PATTERNS="*.test.*,*_test.*,*.mock.*,*.d.ts,dist/*,build/*"
```

---

## 🔄 How It Works

```
git commit -m "feat: add feature"
    │
    ▼
┌───────────────────────────────────────┐
│  Pre-commit Hook (gga run) │
└───────────────────────────────────────┘
    │
    ├──▶ 1. Load config from .gga
    │
    ├──▶ 2. Validate provider is installed
    │
    ├──▶ 3. Check AGENTS.md exists
    │
    ├──▶ 4. Get staged files matching FILE_PATTERNS
    │       (excluding EXCLUDE_PATTERNS)
    │
    ├──▶ 5. Read coding rules from AGENTS.md
    │
    ├──▶ 6. Build prompt: rules + file contents
    │
    ├──▶ 7. Send to AI provider (with timeout + progress)
    │       (claude/gemini/codex/opencode/ollama/lmstudio/github/...)
    │
    └──▶ 8. Parse response
            │
            ├── "STATUS: PASSED" ──▶ ✅ Commit proceeds
            │
            └── "STATUS: FAILED" ──▶ ❌ Commit blocked
                                       (shows violation details)
```

---

## 🚫 Bypass Review

Sometimes you need to commit without review:

```bash
# Skip pre-commit hook entirely
git commit --no-verify -m "wip: work in progress"

# Short form
git commit -n -m "hotfix: urgent fix"
```

---

## 🔗 Integrations

Gentleman Guardian Angel works standalone with native git hooks, but you can also integrate it with popular hook managers.

### Native Git Hook (Default)

This is what `gga install` does automatically:

```bash
# .git/hooks/pre-commit
#!/usr/bin/env bash
gga run || exit 1
```

### Husky (Node.js projects)

[Husky](https://typicode.github.io/husky/) is popular in JavaScript/TypeScript projects.

#### Setup with Husky v9+

```bash
# Install husky
npm install -D husky

# Initialize husky
npx husky init
```

Edit `.husky/pre-commit`:

```bash
#!/usr/bin/env bash

# Run Gentleman Guardian Angel
gga run || exit 1

# Your other checks (optional)
npm run lint
npm run typecheck
```

#### With lint-staged (review only staged files)

```bash
# Install dependencies
npm install -D husky lint-staged
```

`package.json`:

```json
{
  "scripts": {
    "prepare": "husky"
  },
  "lint-staged": {
    "*.{ts,tsx,js,jsx}": ["eslint --fix", "prettier --write"]
  }
}
```

`.husky/pre-commit`:

```bash
#!/usr/bin/env bash

# AI Review first (uses git staged files internally)
gga run || exit 1

# Then lint-staged for formatting
npx lint-staged
```

### pre-commit (Python projects)

[pre-commit](https://pre-commit.com/) is the standard for Python projects.

#### Setup

```bash
# Install pre-commit
pip install pre-commit

# Or with brew
brew install pre-commit
```

Create `.pre-commit-config.yaml`:

```yaml
repos:
  # Gentleman Guardian Angel (runs first)
  - repo: local
    hooks:
      - id: gga
        name: Gentleman Guardian Angel
        entry: gga run
        language: system
        pass_filenames: false
        stages: [pre-commit]

  # Your other hooks
  - repo: https://github.com/psf/black
    rev: 24.4.2
    hooks:
      - id: black

  - repo: https://github.com/pycqa/flake8
    rev: 7.0.0
    hooks:
      - id: flake8

  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.10.0
    hooks:
      - id: mypy
```

Install the hooks:

```bash
pre-commit install
```

#### Running manually

```bash
# Run all hooks
pre-commit run --all-files

# Run only AI review
pre-commit run gga
```

### Lefthook (Fast, language-agnostic)

[Lefthook](https://github.com/evilmartians/lefthook) is a fast Git hooks manager written in Go.

#### Setup

```bash
# Install
brew install lefthook

# Or with npm
npm install -D lefthook
```

Create `lefthook.yml`:

```yaml
pre-commit:
  parallel: false
  commands:
    ai-review:
      run: gga run
      fail_text: "Gentleman Guardian Angel failed. Fix violations before committing."

    lint:
      glob: "*.{ts,tsx,js,jsx}"
      run: npm run lint

    typecheck:
      run: npm run typecheck
```

Install hooks:

```bash
lefthook install
```

### 🖥️ VS Code / Antigravity Integration

GGA works seamlessly with VS Code and [Antigravity](https://antigravity.google) (Google's AI-first IDE). Since GGA installs as a standard git hook, it runs automatically when you commit — regardless of which IDE or terminal you use.

**Setup:**

```bash
# 1. Open your project in VS Code or Antigravity
# 2. Open the integrated terminal (Ctrl+`)
# 3. Initialize and install GGA as usual
gga init
gga install

# 4. Make sure your AI provider CLI is available in PATH
which claude   # or gemini, codex, opencode
```

That's it. When you commit via the Source Control panel (`Cmd+Enter` / `Ctrl+Enter`) or via `git commit` in the terminal, GGA's pre-commit hook fires and reviews your staged files.

**Tips for VS Code / Antigravity users:**

- **Output visibility**: Hook output appears in the "Git" output channel. Open it via View → Output → select "Git" from the dropdown
- **Bypass when needed**: Use `--no-verify` from the terminal: `git commit --no-verify -m "wip"`
- **Antigravity users**: Antigravity includes Gemini built-in. Set `PROVIDER="gemini"` in your `.gga` config and ensure the `gemini` CLI is in your PATH. GGA works through git hooks — no IDE-specific configuration needed.
- **Windows + VS Code**: VS Code may launch Git from a different shell profile than your terminal. Confirm `gga` is resolvable from inside VS Code with `where gga` (PowerShell/CMD) or `which gga` (Git Bash).

### CI/CD Integration

You can also run Gentleman Guardian Angel in your CI pipeline:

#### GitHub Actions

```yaml
# .github/workflows/ai-review.yml
name: Gentleman Guardian Angel

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install Gentleman Guardian Angel
        run: |
          git clone https://github.com/Gentleman-Programming/gentleman-guardian-angel.git /tmp/gga
          chmod +x /tmp/gga/bin/gga
          echo "/tmp/gga/bin" >> $GITHUB_PATH

      - name: Install Claude CLI
        run: |
          # Install your preferred provider CLI
          npm install -g @anthropic-ai/claude-code
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}

      - name: Run AI Review
        run: |
          # Review all files changed in the PR
          gga run --pr-mode

          # Or with diffs only (faster, cheaper)
          # gga run --pr-mode --diff-only
```

#### GitLab CI

```yaml
# .gitlab-ci.yml
gga:
  stage: test
  image: ubuntu:latest
  before_script:
    - apt-get update && apt-get install -y git curl
    - git clone https://github.com/Gentleman-Programming/gentleman-guardian-angel.git /opt/gga
    - export PATH="/opt/gga/bin:$PATH"
    # Install your provider CLI here
  script:
    - git diff --name-only $CI_MERGE_REQUEST_DIFF_BASE_SHA | xargs git add
    - gga run
  only:
    - merge_requests
```

---

## 🐛 Troubleshooting

### "Provider not found"

```bash
# Check if your provider CLI is installed and in PATH
which claude   # Should show: /usr/local/bin/claude or similar
which gemini
which codex
which ollama

# Test if the provider works
echo "Say hello" | claude --print

# For LM Studio, check if the API is accessible
curl http://localhost:1234/v1/models
```

### "Rules file not found"

The tool requires a rules file to know what to check:

```bash
# Create your rules file
touch AGENTS.md

# Add your coding standards
echo "# My Coding Standards" > AGENTS.md
echo "- No console.log in production" >> AGENTS.md
```

### "Ambiguous response" in Strict Mode

The AI must respond with `STATUS: PASSED` or `STATUS: FAILED` as the first line. If it doesn't:

1. Try Claude (most reliable at following instructions)
2. Check your rules file isn't confusing the AI
3. Temporarily disable strict mode: `STRICT_MODE="false"`

### Slow reviews on large files

The tool sends full file contents. For better performance:

```bash
# Add large/generated files to exclude
EXCLUDE_PATTERNS="*.min.js,*.bundle.js,dist/*,build/*,*.generated.ts"
```

### GitHub Models setup

```bash
# 1. Install GitHub CLI
brew install gh

# 2. Authenticate
gh auth login

# 3. Configure GGA
echo 'PROVIDER="github:gpt-4o"' > .gga

# Available models: https://github.com/marketplace/models
```

### Timeout issues

If reviews are timing out (exit code 124):

```bash
# Increase timeout (default: 300s)
TIMEOUT="600"          # In .gga config
GGA_TIMEOUT=600 gga run  # Or via environment variable

# Review fewer files at once
EXCLUDE_PATTERNS="*.min.js,*.bundle.js,dist/*"
```

### GGA not running from VS Code Source Control panel

If GGA doesn't trigger when committing from VS Code's Source Control UI:

1. Ensure the hook is installed: `ls -la .git/hooks/pre-commit`
2. Check that `gga` is in your PATH — VS Code may use a different shell profile
   - On Windows, check both PowerShell (`where gga`) and Git Bash (`which gga`) inside VS Code.
3. Try adding the full path in the hook:
   ```bash
   # .git/hooks/pre-commit
   /opt/homebrew/bin/gga run || exit 1
   ```
4. On Windows, if PATH still differs, hardcode the executable path in the hook (for example `C:/Users/<you>/.local/bin/gga.exe run || exit 1`).
5. Check the Git output channel (View → Output → Git) for error messages

### LM Studio connection issues

If you get "Failed to connect to LM Studio" errors:

1. Ensure LM Studio is running and the API server is enabled
2. Check the API port in LM Studio settings (default: 1234)
3. Verify the host setting:
   ```bash
   # Default
   LMSTUDIO_HOST="http://localhost:1234/v1"

   # Custom port
   LMSTUDIO_HOST="http://localhost:8080/v1"
   ```
4. Test the connection:
   ```bash
   curl http://localhost:1234/v1/models
   ```

---

## 🧪 Development

### Project Structure

```
gentleman-guardian-angel/
├── bin/
│   └── gga                          # Main CLI script
├── lib/
│   ├── providers.sh                 # AI provider implementations
│   ├── cache.sh                     # Smart caching logic
│   └── pr_mode.sh                   # PR review mode functions
├── spec/                            # ShellSpec test suite
│   ├── spec_helper.sh               # Test setup and helpers
│   ├── unit/
│   │   ├── cache_spec.sh            # Cache unit tests
│   │   ├── providers_spec.sh        # Provider unit tests
│   │   ├── github_models_spec.sh    # GitHub Models tests
│   │   ├── pr_mode_spec.sh          # PR mode tests
│   │   ├── timeout_spec.sh          # Timeout/spinner tests
│   │   └── status_parsing_spec.sh   # STATUS parsing tests
│   └── integration/
│       ├── commands_spec.sh         # CLI integration tests
│       ├── ollama_spec.sh           # Ollama integration (local)
│       └── github_models_spec.sh    # GitHub Models integration (local)
├── Makefile                         # Development commands
├── .shellspec                       # Test runner config
├── install.sh                       # Manual installer
├── uninstall.sh                     # Uninstaller
└── README.md
```

### Running Tests

GGA uses [ShellSpec](https://shellspec.info/) for testing - a BDD-style testing framework for shell scripts.

```bash
# Install dependencies (once)
brew install shellspec shellcheck

# Run all tests
make test

# Run specific test suites
make test-unit        # Unit tests only
make test-integration # Integration tests only

# Lint shell scripts with shellcheck
make lint

# Run all checks before commit (lint + tests)
make check
```

### Test Coverage

| Module             | Tests   | Description                                             |
| ------------------ | ------- | ------------------------------------------------------- |
| `cache.sh`         | 26      | Hash functions, cache validation, file caching          |
| `providers.sh`     | 98      | All providers, routing, validation, security            |
| `github_models`    | 16      | GitHub Models provider, API, auth, error handling       |
| `pr_mode`          | 26      | Base branch detection, PR files, diff, prompt building  |
| `timeout`          | 19      | Timeout wrapper, spinner, provider routing              |
| `status_parsing`   | 14      | STATUS: PASSED/FAILED parsing edge cases                |
| Integration        | 34+     | CLI commands, Ollama, GitHub Models (local)             |
| **Total**          | **174** | Full coverage of core functionality                     |

### Adding New Tests

```bash
# Create a new spec file
touch spec/unit/my_feature_spec.sh

# Run only your new tests
shellspec spec/unit/my_feature_spec.sh
```

---

## 📋 Changelog

### v2.7.0 (Latest)

- ✅ **feat**: Timeout & progress feedback for AI provider calls (#35, based on PR #20 by @ramarivera)
  - Configurable `TIMEOUT` (default: 300s) with `GGA_TIMEOUT` env override
  - Visual spinner in TTY mode, periodic text updates in CI/pipes
  - Exit code 124 on timeout with troubleshooting suggestions
  - Generic fallback for unknown/future providers
  - **19 new tests**
- ✅ **feat**: GitHub Models provider (#36, based on PR #3 by @Kyonax)
  - `PROVIDER="github:<model>"` — access GPT-4o, DeepSeek R1, Grok 3, Phi-4, LLaMA, etc.
  - Auth via `gh auth token` — no extra API keys needed
  - Uses python3 for safe JSON (no jq dependency)
  - **16 new tests**
- ✅ **feat**: PR review mode (#37, based on PR #30 by @Jose-cd)
  - `--pr-mode`: review all files changed in the full PR range
  - `--diff-only`: with `--pr-mode`, send only diffs (faster, cheaper)
  - Auto-detects base branch (main/master/develop) with `PR_BASE_BRANCH` config override
  - **26 new tests**
- ✅ **174 tests** total, 0 failures

### v2.6.1

- ✅ **fix**: Relaxed STATUS parsing to handle AI preamble text (#18, PR #19)
  - Search for STATUS in first 15 lines instead of requiring line 1
  - Accept markdown formatting (`**STATUS: PASSED**`)
  - Works with AI agents that have system-wide instruction files (AGENTS.md, CLAUDE.md)
- ✅ **14 new tests** for STATUS parsing edge cases
- ✅ **161 tests** total

### v2.6.0

- ✅ **feat**: Commit message validation support (PR #17, based on #11 by @ramarivera)
  - `gga install --commit-msg` installs commit-msg hook instead of pre-commit
  - Commit message is automatically included in AI review when available
  - No config needed - behavior is automatic based on context
- ✅ **fix**: Read from staging area (`git show :file`) to prevent index corruption (#15, #16)
  - Fixes race conditions when files are modified after staging
  - Works correctly with lint-staged, prettier, and other tools
- ✅ **feat**: Signal handling for graceful cleanup on interruption
- ✅ `gga uninstall` now handles both pre-commit and commit-msg hooks
- ✅ **147 tests** (17 new for commit-msg and staging area fixes)

### v2.5.1

- ✅ **fix(gemini)**: Use `-p` flag for non-interactive prompt passing - fixes exit code 41 in CI
- ✅ **fix(opencode)**: Use positional argument instead of stdin pipe per documentation
- ✅ Both providers now work correctly in CI/non-interactive environments

### v2.5.0

- ✅ **feat**: OpenCode provider support (PR #4 by @ramarivera)
  - `PROVIDER="opencode"` for default model
  - `PROVIDER="opencode:model_name"` for specific models
- ✅ Added `CONTRIBUTING.md` with development guide
- ✅ **130 tests** (12 new for OpenCode)

### v2.4.0

- ✅ **feat**: CI mode (`--ci` flag) for GitHub Actions/GitLab CI
  - Reviews files from last commit (`HEAD~1..HEAD`) instead of staged files
  - Cache automatically disabled in CI mode
- ✅ **118 tests** (6 new for CI mode)

### v2.3.0

- ✅ Fixed Ollama ANSI escape codes breaking STATUS parsing (#6)
- ✅ New `execute_ollama_api()` using curl for clean JSON responses
- ✅ Fallback `execute_ollama_cli()` with ANSI stripping
- ✅ Security validation for `OLLAMA_HOST`
- ✅ Worktree support and improved hook install/uninstall (PR #10 by @ramarivera)
- ✅ Best practices docs for AGENTS.md rules file
- ✅ GitHub Actions CI pipeline (lint, unit tests, integration tests)
- ✅ Expanded test suite to **104 tests**

### v2.2.0

- ✅ Added comprehensive test suite with **68 tests**
- ✅ Unit tests for `cache.sh` and `providers.sh`
- ✅ Integration tests for all CLI commands
- ✅ Added `Makefile` with `test`, `lint`, `check` targets
- ✅ Fixed shellcheck warnings

### v2.1.0

- ✅ Smart caching system - skip unchanged files
- ✅ Auto-invalidation when AGENTS.md or .gga changes
- ✅ Cache commands: `status`, `clear`, `clear-all`
- ✅ `--no-cache` flag to bypass caching

### v2.0.0

- ✅ Renamed to Gentleman Guardian Angel (gga)
- ✅ Auto-migration from legacy `ai-code-review` hooks
- ✅ Homebrew tap distribution

### v1.0.0

- ✅ Initial release with Claude, Gemini, Codex, Ollama support
- ✅ File patterns and exclusions
- ✅ Strict mode for CI/CD

---

## 🤝 Contributing

Contributions are welcome! Some ideas:

- [ ] Add more providers (Copilot, Codeium, etc.)
- [ ] Support for `.gga.yaml` format
- [x] ~~Caching to avoid re-reviewing unchanged files~~ ✅ Done in v2.1.0
- [x] ~~Add test suite~~ ✅ Done in v2.2.0
- [x] ~~CI mode for GitHub Actions/GitLab~~ ✅ Done in v2.4.0
- [x] ~~OpenCode provider~~ ✅ Done in v2.5.0 (by @ramarivera)
- [x] ~~Timeout & progress feedback~~ ✅ Done in v2.7.0 (based on @ramarivera)
- [x] ~~GitHub Models provider~~ ✅ Done in v2.7.0 (based on @Kyonax)
- [x] ~~PR review mode~~ ✅ Done in v2.7.0 (based on @Jose-cd)
- [ ] Configurable temperature per provider
- [ ] GitHub Action version
- [ ] Output formats (JSON, SARIF for IDE integration)

```bash
# Fork, clone, and submit PRs!
git clone https://github.com/Gentleman-Programming/gentleman-guardian-angel.git
cd gentleman-guardian-angel

# Run tests before submitting
make check
```

---

## 📄 License

MIT © 2024

---

<p align="center">
  <sub>Built with 🧉 by developers who got tired of repeating the same code review comments</sub>
</p>
