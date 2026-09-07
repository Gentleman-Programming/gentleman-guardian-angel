# Examples

> 📖 Back to [README](../README.md)

Real-world walkthrough and project configuration examples for Gentleman Guardian Angel.

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
    │       (claude/agy/codex/opencode/ollama/lmstudio/github/...)
    │
    └──▶ 8. Parse response
            │
            ├── "STATUS: PASSED" ──▶ ✅ Commit proceeds
            │
            └── "STATUS: FAILED" ──▶ ❌ Commit blocked
                                       (shows violation details)
```

---

## 🎬 Real World Example

Let's walk through a complete example from setup to commit:

### Step 1: Setup in your project

```bash
$ cd ~/projects/my-react-app

$ gga init

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Gentleman Guardian Angel v2.8.0
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
  Gentleman Guardian Angel v2.8.0
  Provider-agnostic code review using AI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Installed pre-commit hook: /Users/dev/projects/my-react-app/.git/hooks/pre-commit
```

### Step 5: Make some changes and commit

```bash
$ git add src/components/Button.tsx
$ git commit -m "feat: add new button component"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Gentleman Guardian Angel v2.8.0
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
  Gentleman Guardian Angel v2.8.0
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
PROVIDER="agy"
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
