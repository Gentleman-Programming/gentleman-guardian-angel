<p align="center">
  <img src="https://img.shields.io/badge/version-1.0.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License">
  <img src="https://img.shields.io/badge/bash-5.0%2B-orange.svg" alt="Bash">
  <img src="https://img.shields.io/badge/homebrew-tap-FBB040.svg" alt="Homebrew">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs Welcome">
</p>

<h1 align="center">🤖 AI Code Review</h1>

<p align="center">
  <strong>Provider-agnostic code review using AI</strong><br>
  Use Claude, Gemini, Codex, Ollama, or any AI to enforce your coding standards.<br>
  Zero dependencies. Pure Bash. Works everywhere.
</p>

<p align="center">
  <a href="#-installation">Installation</a> •
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-providers">Providers</a> •
  <a href="#-commands">Commands</a> •
  <a href="#-configuration">Configuration</a> •
  <a href="#-real-world-example">Example</a>
</p>

---

## 🎯 Why?

You have coding standards. Your team ignores them. Code reviews catch issues too late.

**AI Code Review** runs on every commit, validating your staged files against your project's `AGENTS.md` (or any rules file). It's like having a senior developer review every line before it hits the repo.

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
- 🍺 **Homebrew ready** - One command install

---

## 📦 Installation

### Homebrew (Recommended) 🍺

```bash
brew tap gentleman-programming/tap
brew install ai-code-review
```

Or in a single command:

```bash
brew install gentleman-programming/tap/ai-code-review
```

### Manual Installation

```bash
git clone https://github.com/Gentleman-Programming/ai-code-review.git
cd ai-code-review
./install.sh
```

### Verify Installation

```bash
ai-code-review version
# Output: ai-code-review v1.0.0
```

---

## 🚀 Quick Start

```bash
# 1. Go to your project
cd ~/your-project

# 2. Initialize config
ai-code-review init

# 3. Create your rules file
touch AGENTS.md  # Add your coding standards

# 4. Install the git hook
ai-code-review install

# 5. Done! Now every commit gets reviewed 🎉
```

---

## 🎬 Real World Example

Let's walk through a complete example from setup to commit:

### Step 1: Setup in your project

```bash
$ cd ~/projects/my-react-app

$ ai-code-review init

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  AI Code Review v1.0.0
  Provider-agnostic code review using AI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Created config file: .ai-code-review

ℹ️  Next steps:
  1. Edit .ai-code-review to set your preferred provider
  2. Create AGENTS.md with your coding standards
  3. Run: ai-code-review install
```

### Step 2: Configure your provider

```bash
$ cat .ai-code-review

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
$ ai-code-review install

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  AI Code Review v1.0.0
  Provider-agnostic code review using AI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Installed pre-commit hook: /Users/dev/projects/my-react-app/.git/hooks/pre-commit
```

### Step 5: Make some changes and commit

```bash
$ git add src/components/Button.tsx
$ git commit -m "feat: add new button component"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  AI Code Review v1.0.0
  Provider-agnostic code review using AI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ℹ️  Provider: claude
ℹ️  Rules file: AGENTS.md
ℹ️  File patterns: *.ts,*.tsx,*.js,*.jsx

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
  AI Code Review v1.0.0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ℹ️  Provider: claude
ℹ️  Files to review:
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

| Command | Description | Example |
|---------|-------------|---------|
| `init` | Create sample `.ai-code-review` config file | `ai-code-review init` |
| `install` | Install git pre-commit hook in current repo | `ai-code-review install` |
| `uninstall` | Remove git pre-commit hook from current repo | `ai-code-review uninstall` |
| `run` | Run code review manually on staged files | `ai-code-review run` |
| `config` | Display current configuration and status | `ai-code-review config` |
| `help` | Show help message with all commands | `ai-code-review help` |
| `version` | Show installed version | `ai-code-review version` |

### Command Details

#### `ai-code-review init`

Creates a sample `.ai-code-review` configuration file in your project root with sensible defaults.

```bash
$ ai-code-review init
✅ Created config file: .ai-code-review
```

#### `ai-code-review install`

Installs a git pre-commit hook that automatically runs code review on every commit.

```bash
$ ai-code-review install
✅ Installed pre-commit hook: .git/hooks/pre-commit
```

If a pre-commit hook already exists, it will ask if you want to append to it.

#### `ai-code-review uninstall`

Removes the git pre-commit hook from your repository.

```bash
$ ai-code-review uninstall
✅ Removed pre-commit hook
```

#### `ai-code-review run`

Manually runs code review on currently staged files. Useful for testing before committing.

```bash
$ git add src/components/Button.tsx
$ ai-code-review run
# Reviews the staged file
```

#### `ai-code-review config`

Shows the current configuration, including where config files are loaded from and all settings.

```bash
$ ai-code-review config

Current Configuration:

Config Files:
  Global:  Not found
  Project: .ai-code-review

Values:
  PROVIDER:          claude
  FILE_PATTERNS:     *.ts,*.tsx,*.js,*.jsx
  EXCLUDE_PATTERNS:  *.test.ts,*.spec.ts
  RULES_FILE:        AGENTS.md
  STRICT_MODE:       true

Rules File: Found
```

---

## 🔌 Providers

Use whichever AI CLI you have installed:

| Provider | Config Value | CLI Command Used | Installation |
|----------|-------------|------------------|--------------|
| **Claude** | `claude` | `echo "prompt" \| claude --print` | [claude.ai/code](https://claude.ai/code) |
| **Gemini** | `gemini` | `echo "prompt" \| gemini` | [github.com/google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli) |
| **Codex** | `codex` | `codex exec "prompt"` | `npm i -g @openai/codex` |
| **Ollama** | `ollama:<model>` | `ollama run <model> "prompt"` | [ollama.ai](https://ollama.ai) |

### Provider Examples

```bash
# Use Claude (recommended - most reliable)
PROVIDER="claude"

# Use Google Gemini
PROVIDER="gemini"

# Use OpenAI Codex
PROVIDER="codex"

# Use Ollama with Llama 3.2
PROVIDER="ollama:llama3.2"

# Use Ollama with CodeLlama (optimized for code)
PROVIDER="ollama:codellama"

# Use Ollama with Qwen Coder
PROVIDER="ollama:qwen2.5-coder"

# Use Ollama with DeepSeek Coder
PROVIDER="ollama:deepseek-coder"
```

---

## ⚙️ Configuration

### Config File: `.ai-code-review`

Create this file in your project root:

```bash
# AI Provider (required)
# Options: claude, gemini, codex, ollama:<model>
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
```

### Configuration Options

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `PROVIDER` | ✅ Yes | - | AI provider to use |
| `FILE_PATTERNS` | No | `*` | Comma-separated file patterns to include |
| `EXCLUDE_PATTERNS` | No | - | Comma-separated file patterns to exclude |
| `RULES_FILE` | No | `AGENTS.md` | Path to your coding standards file |
| `STRICT_MODE` | No | `true` | Fail on ambiguous AI responses |

### Config Hierarchy (Priority Order)

1. **Environment variable** `AI_CODE_REVIEW_PROVIDER` (highest priority)
2. **Project config** `.ai-code-review` (in project root)
3. **Global config** `~/.config/ai-code-review/config` (lowest priority)

```bash
# Override provider for a single run
AI_CODE_REVIEW_PROVIDER="gemini" ai-code-review run

# Or export for the session
export AI_CODE_REVIEW_PROVIDER="ollama:llama3.2"
```

---

## 📝 Rules File (AGENTS.md)

The AI needs to know your standards. Create an `AGENTS.md` file:

```markdown
# Code Review Rules

## TypeScript
- Use `const` and `let`, never `var`
- No `any` types - always use proper typing
- Prefer interfaces over type aliases for objects
- Use optional chaining (`?.`) and nullish coalescing (`??`)

## React
- Functional components only, no class components
- No `import * as React` - use named imports
- Use semantic HTML elements
- All images need alt text
- Interactive elements need aria labels

## Styling
- Use Tailwind CSS utilities
- No inline styles
- No hex colors - use design tokens

## Testing
- All new features need tests
- Test files must be co-located with source files
- Use descriptive test names that explain the behavior
```

> 💡 **Pro tip**: Your `AGENTS.md` can also serve as documentation for human reviewers!

---

## 🎨 Project Examples

### TypeScript/React Project

```bash
# .ai-code-review
PROVIDER="claude"
FILE_PATTERNS="*.ts,*.tsx"
EXCLUDE_PATTERNS="*.test.ts,*.test.tsx,*.spec.ts,*.d.ts,*.stories.tsx"
RULES_FILE="AGENTS.md"
```

### Python Project

```bash
# .ai-code-review
PROVIDER="ollama:codellama"
FILE_PATTERNS="*.py"
EXCLUDE_PATTERNS="*_test.py,test_*.py,conftest.py,__pycache__/*"
RULES_FILE=".coding-standards.md"
```

### Go Project

```bash
# .ai-code-review
PROVIDER="gemini"
FILE_PATTERNS="*.go"
EXCLUDE_PATTERNS="*_test.go,mock_*.go,*_mock.go"
```

### Full-Stack Monorepo

```bash
# .ai-code-review
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
│  Pre-commit Hook (ai-code-review run) │
└───────────────────────────────────────┘
    │
    ├──▶ 1. Load config from .ai-code-review
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
    ├──▶ 7. Send to AI provider (claude/gemini/codex/ollama)
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

---

## 🤝 Contributing

Contributions are welcome! Some ideas:

- [ ] Add more providers (Copilot, Codeium, etc.)
- [ ] Support for `.ai-code-review.yaml` format  
- [ ] Caching to avoid re-reviewing unchanged files
- [ ] GitHub Action version
- [ ] Output formats (JSON, SARIF for IDE integration)

```bash
# Fork, clone, and submit PRs!
git clone https://github.com/Gentleman-Programming/ai-code-review.git
```

---

## 📄 License

MIT © 2024

---

<p align="center">
  <sub>Built with 🧉 by developers who got tired of repeating the same code review comments</sub>
</p>
