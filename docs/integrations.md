# Integrations

> 📖 Back to [README](../README.md)

Gentleman Guardian Angel works standalone with native git hooks, but you can also integrate it with popular hook managers and CI/CD pipelines.

---

## Native Git Hook (Default)

This is what `gga install` does automatically:

```bash
# .git/hooks/pre-commit
#!/usr/bin/env bash
gga run || exit 1
```

---

## Husky (Node.js projects)

[Husky](https://typicode.github.io/husky/) is popular in JavaScript/TypeScript projects.

### Setup with Husky v9+

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

### With lint-staged (review only staged files)

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

---

## pre-commit (Python projects)

[pre-commit](https://pre-commit.com/) is the standard for Python projects.

### Setup

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

### Running manually

```bash
# Run all hooks
pre-commit run --all-files

# Run only AI review
pre-commit run gga
```

---

## Lefthook (Fast, language-agnostic)

[Lefthook](https://github.com/evilmartians/lefthook) is a fast Git hooks manager written in Go.

### Setup

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

---

## 🖥️ VS Code / Antigravity Integration

GGA works seamlessly with VS Code and [Antigravity](https://antigravity.google) (Google's AI-first IDE). Since GGA installs as a standard git hook, it runs automatically when you commit — regardless of which IDE or terminal you use.

**Setup:**

```bash
# 1. Open your project in VS Code or Antigravity
# 2. Open the integrated terminal (Ctrl+`)
# 3. Initialize and install GGA as usual
gga init
gga install

# 4. Make sure your AI provider CLI is available in PATH
which claude   # or agy, codex, opencode
```

That's it. When you commit via the Source Control panel (`Cmd+Enter` / `Ctrl+Enter`) or via `git commit` in the terminal, GGA's pre-commit hook fires and reviews your staged files.

**Tips for VS Code / Antigravity users:**

- **Output visibility**: Hook output appears in the "Git" output channel. Open it via View → Output → select "Git" from the dropdown
- **Bypass when needed**: Use `--no-verify` from the terminal: `git commit --no-verify -m "wip"`
- **Antigravity users**: Antigravity ships the `agy` CLI. Set `PROVIDER="agy"` in your `.gga` config and ensure `agy` is in your PATH (`agy install`). GGA works through git hooks — no IDE-specific configuration needed.
- **Windows + VS Code**: VS Code may launch Git from a different shell profile than your terminal. Confirm `gga` is resolvable from inside VS Code with `where gga` (PowerShell/CMD) or `which gga` (Git Bash).

---

## CI/CD Integration

You can also run Gentleman Guardian Angel in your CI pipeline:

### GitHub Actions

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

### GitLab CI

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
