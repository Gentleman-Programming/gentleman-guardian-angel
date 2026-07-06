# Changelog

> 📖 Back to [README](../README.md)

Full version history for Gentleman Guardian Angel.

---

## v2.10.0 (Latest)

- ✅ **feat(providers)**: Added Kiro CLI provider support
  - `PROVIDER="kiro"` for Kiro CLI headless review
  - Full GGA review prompts are sent through stdin/temp-file handoff to avoid ARG_MAX failures
  - Kiro receives only a short required headless instruction as argv
  - Inline `kiro:model` configuration is rejected; model selection stays in Kiro CLI settings
- ✅ **docs(providers)**: Updated provider tables and examples for Kiro
- ✅ CI green for lint, unit tests, integration tests, PR validation, and CodeRabbit

---

## v2.9.0

- ✅ **feat(providers)**: Added Cursor Agent, Kilo, and MiniMax provider support
  - `PROVIDER="cursor[:model]"` for Cursor Agent CLI, including legacy `agent` fallback
  - `PROVIDER="kilo[:model]"` for Kilo CLI with non-interactive stdin prompt handoff
  - `PROVIDER="minimax[:model]"` for MiniMax Chat Completions API, defaulting to `MiniMax-M3`
- ✅ **fix(providers)**: Hardened large-prompt handling across CLI and API providers
  - CLI providers use stdin/temp-file handoff to avoid ARG_MAX failures
  - Ollama API, LM Studio, GitHub Models, and MiniMax send JSON payloads through curl stdin
  - MiniMax keeps API keys out of curl argv by using a temporary curl config file
- ✅ **fix(timeout)**: Provider timeout cleanup now terminates child processes that survive `TERM`
- ✅ **fix(windows)**: Improved Windows/Git Bash reliability
  - Normalize Windows-style `APPDATA`, `XDG_CONFIG_HOME`, and `LOCALAPPDATA` paths with `cygpath` when available
  - Load CRLF and UTF-8 BOM `.gga` config files without modifying user files
  - Add installed-library fallback for stale or mixed Windows/WSL `LIB_DIR` paths
  - Fix literal ANSI escape rendering in help output
- ✅ **fix(run)**: Hardened Codex final-message output and STATUS parsing from previous provider work
- ✅ CI green for lint, unit tests, integration tests, and PR validation

---

## v2.8.1

- ✅ **fix(release)**: Replace hardcoded version with release-injected version support
- ✅ **ci(release)**: Add automated tag-based GitHub release and Homebrew tap update workflow

---

## v2.8.0

- ✅ **feat**: Windows Git Bash support (MINGW64)
  - GGA now runs natively on Windows through Git Bash with no special configuration
  - `bash install.sh` works correctly in MINGW64 environment
  - PATH setup documented for Windows users
  - Platforms badge updated: macOS | Linux | Windows
- ✅ **266 tests** total, 0 failures

---

## v2.7.3

- ✅ **fix**: Platforms badge updated to include Windows
- ✅ **fix**: Version badge updated to reflect current release
- ✅ Minor documentation improvements

---

## v2.7.0

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

---

## v2.6.1

- ✅ **fix**: Relaxed STATUS parsing to handle AI preamble text (#18, PR #19)
  - Search for STATUS in first 15 lines instead of requiring line 1
  - Accept markdown formatting (`**STATUS: PASSED**`)
  - Works with AI agents that have system-wide instruction files (AGENTS.md, CLAUDE.md)
- ✅ **14 new tests** for STATUS parsing edge cases
- ✅ **161 tests** total

---

## v2.6.0

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

---

## v2.5.1

- ✅ **fix(gemini)**: Use `-p` flag for non-interactive prompt passing - fixes exit code 41 in CI
- ✅ **fix(opencode)**: Use positional argument instead of stdin pipe per documentation
- ✅ Both providers now work correctly in CI/non-interactive environments

---

## v2.5.0

- ✅ **feat**: OpenCode provider support (PR #4 by @ramarivera)
  - `PROVIDER="opencode"` for default model
  - `PROVIDER="opencode:model_name"` for specific models
- ✅ Added `CONTRIBUTING.md` with development guide
- ✅ **130 tests** (12 new for OpenCode)

---

## v2.4.0

- ✅ **feat**: CI mode (`--ci` flag) for GitHub Actions/GitLab CI
  - Reviews files from last commit (`HEAD~1..HEAD`) instead of staged files
  - Cache automatically disabled in CI mode
- ✅ **118 tests** (6 new for CI mode)

---

## v2.3.0

- ✅ Fixed Ollama ANSI escape codes breaking STATUS parsing (#6)
- ✅ New `execute_ollama_api()` using curl for clean JSON responses
- ✅ Fallback `execute_ollama_cli()` with ANSI stripping
- ✅ Security validation for `OLLAMA_HOST`
- ✅ Worktree support and improved hook install/uninstall (PR #10 by @ramarivera)
- ✅ Best practices docs for AGENTS.md rules file
- ✅ GitHub Actions CI pipeline (lint, unit tests, integration tests)
- ✅ Expanded test suite to **104 tests**

---

## v2.2.0

- ✅ Added comprehensive test suite with **68 tests**
- ✅ Unit tests for `cache.sh` and `providers.sh`
- ✅ Integration tests for all CLI commands
- ✅ Added `Makefile` with `test`, `lint`, `check` targets
- ✅ Fixed shellcheck warnings

---

## v2.1.0

- ✅ Smart caching system - skip unchanged files
- ✅ Auto-invalidation when AGENTS.md or .gga changes
- ✅ Cache commands: `status`, `clear`, `clear-all`
- ✅ `--no-cache` flag to bypass caching

---

## v2.0.0

- ✅ Renamed to Gentleman Guardian Angel (gga)
- ✅ Auto-migration from legacy `ai-code-review` hooks
- ✅ Homebrew tap distribution

---

## v1.0.0

- ✅ Initial release with Claude, Gemini, Codex, Ollama support
- ✅ File patterns and exclusions
- ✅ Strict mode for CI/CD
