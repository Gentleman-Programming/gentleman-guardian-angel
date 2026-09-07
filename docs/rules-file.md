# Rules File (AGENTS.md)

> 📖 Back to [README](../README.md)

Everything you need to know about writing effective `AGENTS.md` coding standards files for GGA.

---

## 📝 Overview

The AI needs to know your standards. Create an `AGENTS.md` file in your project root.

Your rules file should be **optimized for LLM parsing**, not for human documentation. Here's why and how:

---

## Best Practices

### 1. Keep it Concise (~100-200 lines)

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

### 2. Use Clear Action Keywords

Use `REJECT`, `REQUIRE`, `PREFER` to give the AI clear signals:

| Keyword     | Meaning              | AI Action                           |
| ----------- | -------------------- | ----------------------------------- |
| `REJECT if` | Hard rule, must fail | Returns `STATUS: FAILED`            |
| `REQUIRE`   | Mandatory pattern    | Returns `STATUS: FAILED` if missing |
| `PREFER`    | Soft recommendation  | May note but won't fail             |

### 3. Use References for Complex Projects

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

**Why references work:** Claude, Antigravity, and Codex have built-in tools to read files. When they see a reference like "`ui/AGENTS.md`", they can go read it if they need more context. This keeps your main file focused while allowing deep dives when needed.

> ⚠️ **Note for Ollama users**: Ollama is a pure LLM without file-reading tools. If you use Ollama and need multiple rules files, you'll need to manually consolidate them into one file.

### 4. Structure for Scanning

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

### 5. Real-World Example

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

### 6. Use Skills for Large or Multi-Stack Projects

Instead of cramming every rule into a single file (which adds noise and dilutes the AI's focus), use a **skill-based approach**: define an index of triggers and skills, and let the AI load only what's relevant for the files being reviewed.

**Why this matters:**
- More context ≠ better reviews. Large prompts introduce noise that degrades AI response quality.
- A focused, small prompt with only the relevant rules produces significantly better results.
- This also avoids OS-level argument size limits (`ARG_MAX`) that can cause failures on large PRs.

**How it works:**

Your `AGENTS.md` has two parts:
1. **A skill index** — maps file patterns to skill files with specific rules
2. **General rules** — always-on rules that apply to every file

```markdown
# Code Review Rules

## Skill Index

| Trigger (file pattern) | Skill | Location |
|------------------------|-------|----------|
| `*.ts`, `*.tsx` | TypeScript | `docs/skills/typescript.md` |
| `*.tsx`, `*.jsx` | React | `docs/skills/react.md` |
| `*.css`, `*.scss`, `className=` | Styling | `docs/skills/tailwind.md` |
| `*.py` | Python | `docs/skills/python.md` |
| `*.test.*`, `*.spec.*` | Testing | `docs/skills/testing.md` |
| `*.go` | Go | `docs/skills/go.md` |
| `Dockerfile`, `*.yml` | Infrastructure | `docs/skills/infra.md` |

---

## General Rules (always active)

REJECT if:
- Hardcoded secrets or credentials
- `console.log` / `print()` in production code
- Empty catch/except blocks (silent error swallowing)
- Code duplication (DRY violation)
- Missing error handling

REQUIRE:
- Descriptive variable and function names
- Error messages that help debugging

## Response Format

FIRST LINE must be exactly:
STATUS: PASSED
or
STATUS: FAILED

If FAILED, list: `file:line - rule violated - issue`
```

Each skill file is a focused, self-contained set of rules:

```markdown
<!-- docs/skills/typescript.md -->
# TypeScript Review Rules

REJECT if:
- `any` type without `// @ts-expect-error` justification
- Missing return types on exported functions
- Type assertions (`as X`) without comment explaining why
- `enum` used → use `as const` objects instead

PREFER:
- Discriminated unions over type guards
- `satisfies` over type assertions
- Named exports over default exports
```

```markdown
<!-- docs/skills/react.md -->
# React Review Rules

REJECT if:
- `import React` → use named imports `import { useState }`
- `useMemo`/`useCallback` without justification (React 19 Compiler handles this)
- Missing `"use client"` directive in client components
- Props drilling more than 2 levels deep

PREFER:
- Composition over inheritance
- Semantic HTML (`<section>`, `<article>`) over generic `<div>`
- Colocated files (component + test + styles in same directory)
```

**The AI sees the index, checks which files are in the diff, and reads only the relevant skill files.** A PR that only touches `.py` files won't load React or TypeScript rules — the AI gets a clean, focused prompt with just what it needs.

> ⚠️ **Note**: This works best with providers that have file-reading capabilities (Claude, Antigravity, Codex). For Ollama or other pure LLMs without tool use, you'll need to keep rules in a single file.
