#!/usr/bin/env bash
if (set -o pipefail 2>/dev/null); then set -euo pipefail; else set -eu; fi
shopt -s nullglob 2>/dev/null || true
# Gentleman Agent — Linux/macOS environment setup (wrapper)
# Calls setup-machine.sh for all env/shortcut/skill config,
# then checks for optional gentle-ai CLI dependency.
#
# Usage:
#   ./scripts/install.sh                           # interactive
#   ./scripts/install.sh --yes                     # non-interactive
#   ./scripts/install.sh --install-gentle-ai       # deprecated, throws error
#   ./scripts/install.sh --skip-shortcuts          # no shell wrappers
#   ./scripts/install.sh --skip-env-var            # CI/containers

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { printf '%s==>%s %s\n' "$CYAN" "$NC" "$*"; }
ok()    { printf '%s[ok]%s %s\n' "$GREEN" "$NC" "$*"; }
warn()  { printf '%s[warn]%s %s\n' "$YELLOW" "$NC" "$*"; }

INSTALL_GENTLE_AI=false
SKIP_SHORTCUTS=false
SKIP_ENV_VAR=false
while [ $# -gt 0 ]; do
    case "$1" in
        --yes) :; shift ;;  # accepted for CI compatibility; setup is non-interactive
        --install-gentle-ai) INSTALL_GENTLE_AI=true; shift ;;
        --skip-shortcuts) SKIP_SHORTCUTS=true; shift ;;
        --skip-env-var) SKIP_ENV_VAR=true; shift ;;
        --help|-h) echo "Usage: install.sh [--yes] [--install-gentle-ai] [--skip-shortcuts] [--skip-env-var]"; exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
info "Gentleman Agent — Linux/macOS setup"
info "Repo: ${REPO_DIR}\n"

# ── Step 1: Run setup-machine.sh ──────────────────────────────────────
SETUP_ARGS=""
if [ "$SKIP_ENV_VAR" = true ]; then SETUP_ARGS="${SETUP_ARGS} --skip-env-var"; fi
if [ "$SKIP_SHORTCUTS" = true ]; then SETUP_ARGS="${SETUP_ARGS} --skip-shortcuts"; fi
# shellcheck disable=SC2086
if ! "${REPO_DIR}/scripts/setup-machine.sh" --repo-dir "${REPO_DIR}" ${SETUP_ARGS}; then
    warn "setup-machine.sh reported warnings — continuing with partial setup..."
fi

# ── Step 2: Optional gentle-ai CLI ────────────────────────────────────
# NOTE: This repo (gentleman-agent-gh) does NOT install gentle-ai by default.
# The --install-gentle-ai flag is deprecated to prevent accidentally shadowing
# the local environment with a different upstream tool.
if [ "$INSTALL_GENTLE_AI" = true ]; then
    echo ""
    printf '%s--install-gentle-ai is no longer supported.%s\n' "$RED" "$NC"
    printf "Install gentle-ai CLI separately from: https://github.com/Gentleman-Programming/gentle-ai\n"
    exit 1
fi

if ! command -v gentle-ai &>/dev/null; then
    printf '%s[info]%s gentle-ai CLI not found. This is optional — gentleman-agent-gh works without it.\n' "$YELLOW" "$NC"
    printf "       To install gentle-ai separately, visit: https://github.com/Gentleman-Programming/gentle-ai\n"
else
    ok "gentle-ai CLI detected (optional dependency)"
fi

# ── Done ──────────────────────────────────────────────────────────────
echo ""
printf '%s✅ gentleman-agent-gh setup complete%s\n' "$GREEN" "$NC"
echo ""
echo "  Run 'gentleman-vmk' to launch"
