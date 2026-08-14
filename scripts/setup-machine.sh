#!/usr/bin/env bash
# Gentleman Agent — Linux/macOS one-shot machine setup
# Port of scripts/setup-machine.ps1 for POSIX shells.
# Creates global shortcuts, sets env vars, links skills, verifies.
#
# Usage:
#   ./scripts/setup-machine.sh                           # interactive
#   ./scripts/setup-machine.sh --repo-dir /path/to/repo  # from anywhere
#   ./scripts/setup-machine.sh --skip-env-var            # CI/containers
#   ./scripts/setup-machine.sh --skip-shortcuts          # no shell wrappers

if (set -o pipefail 2>/dev/null); then set -euo pipefail; else set -eu; fi
shopt -s nullglob 2>/dev/null || true

# ── Colors ───────────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'
info()  { printf '%s==>%s %s\n' "$CYAN" "$NC" "$*"; }
ok()    { printf '%s[ok]%s %s\n' "$GREEN" "$NC" "$*"; }
warn()  { printf '%s[warn]%s %s\n' "$YELLOW" "$NC" "$*"; }
err()   { printf '%s[err]%s %s\n' "$RED" "$NC" "$*"; exit 1; }
skip()  { printf '%s[skip]%s %s\n' "$DIM" "$NC" "$*"; }

# ── Args ─────────────────────────────────────────────────────────────
REPO_DIR=""
SKIP_ENV_VAR=false
SKIP_SHORTCUTS=false
while [ $# -gt 0 ]; do
    case "$1" in
        --repo-dir) REPO_DIR="$2"; shift 2 ;;
        --repo-dir=*) REPO_DIR="${1#*=}"; shift ;;
        --skip-env-var) SKIP_ENV_VAR=true; shift ;;
        --skip-shortcuts) SKIP_SHORTCUTS=true; shift ;;
        --help|-h) echo "Usage: setup-machine.sh [--repo-dir PATH] [--skip-env-var] [--skip-shortcuts]"; exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

if [ -z "$REPO_DIR" ]; then
    REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fi

# ── Validate repo ───────────────────────────────────────────────────
info "Validating repo at ${REPO_DIR}"
for f in "opencode.json" "AGENTS.md" ".agents/skills"; do
    if [ ! -e "${REPO_DIR}/${f}" ]; then
        err "Missing ${f} — is ${REPO_DIR} the gentleman-agent-gh repo?"
    fi
done
ok "Repo structure validated"

# ── Step 1: GENTLEMAN_AGENT_ROOT ────────────────────────────────────
_upsert_env_var() {
    local name="$1" value="$2"
    # Already set in this shell?
    if [ "${!name:-}" = "$value" ]; then
        return 0
    fi
    export "${name}=${value}"
    # Persist in shell rc
    for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
        [ -f "$rc" ] || continue
        if grep -q "export ${name}=" "$rc" 2>/dev/null; then
            # Update existing
            if [ "$(uname)" = "Darwin" ]; then
                sed -i '' "s|export ${name}=.*|export ${name}=\"${value}\"|" "$rc"
            else
                sed -i "s|export ${name}=.*|export ${name}=\"${value}\"|" "$rc"
            fi
        else
            printf '\n# Gentleman Agent\nexport %s="%s"\n' "$name" "$value" >> "$rc"
        fi
    done
    return 1  # was updated
}

if [ "$SKIP_ENV_VAR" = false ]; then
    info "Setting GENTLEMAN_AGENT_ROOT → ${REPO_DIR}"
    if _upsert_env_var "GENTLEMAN_AGENT_ROOT" "$REPO_DIR"; then
        skip "GENTLEMAN_AGENT_ROOT already set correctly"
    else
        ok "GENTLEMAN_AGENT_ROOT set (restart shell or source ~/.bashrc)"
    fi
else
    skip "GENTLEMAN_AGENT_ROOT (via --skip-env-var)"
fi

# ── Step 2: OpenCode env vars ───────────────────────────────────────
# NOTE: Do NOT set OPENCODE_CONFIG_DIR/CACHE_DIR/DB here — those would
# override ~/.config/opencode/ and break the global install. OpenCode
# uses its defaults (global config dir) automatically.
if [ "$SKIP_ENV_VAR" = false ]; then
    info "Setting OpenCode environment variables"
    declare -A OC_VARS
    OC_VARS["OPENCODE_DISABLE_EMBEDDED_WEB_UI"]="true"
    OC_VARS["OPENCODE_DISABLE_MODELS_FETCH"]="true"
    OC_VARS["OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER"]="true"

    for key in "${!OC_VARS[@]}"; do
        if _upsert_env_var "$key" "${OC_VARS[$key]}"; then
            skip "${key} already set"
        else
            ok "${key} set"
        fi
    done
else
    skip "OpenCode env vars (via --skip-env-var)"
fi

# ── Step 3: Global shortcuts ────────────────────────────────────────
if [ "$SKIP_SHORTCUTS" = false ]; then
    info "Creating global shell shortcuts"
    BIN_DIR="${HOME}/.local/bin"
    mkdir -p "$BIN_DIR"

    # gentleman-vmk
    if [ ! -f "${BIN_DIR}/gentleman-vmk" ]; then
        cat > "${BIN_DIR}/gentleman-vmk" << 'SCRIPT'
#!/usr/bin/env bash
exec opencode --agent gentleman-vMK "$@"
SCRIPT
        chmod +x "${BIN_DIR}/gentleman-vmk"
        ok "Created ${BIN_DIR}/gentleman-vmk"
    else
        skip "${BIN_DIR}/gentleman-vmk already exists"
    fi

    # Add ~/.local/bin to PATH if not already
    case ":${PATH}:" in
        *:"${BIN_DIR}":*) ;;
        *)
            warn "${BIN_DIR} not in PATH — add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to ~/.bashrc"
            ;;
    esac
else
    skip "Global shortcuts (via --skip-shortcuts)"
fi

# ── Step 4: Global opencode config ──────────────────────────────────
info "Syncing global opencode config from repo"
GLOBAL_CONFIG="${HOME}/.config/opencode/opencode.json"
REPO_CONFIG="${REPO_DIR}/opencode.json"

if [ -f "$GLOBAL_CONFIG" ] && [ -f "$REPO_CONFIG" ]; then
    # Use jq if available, otherwise minimal sed approach
    if command -v jq &>/dev/null; then
        updated=false

        # default_agent
        current_agent
        current_agent=$(jq -r '.default_agent // ""' "$GLOBAL_CONFIG")
        if [ "$current_agent" != "gentleman-vMK" ]; then
            jq '.default_agent = "gentleman-vMK"' "$GLOBAL_CONFIG" > "${GLOBAL_CONFIG}.tmp" && mv "${GLOBAL_CONFIG}.tmp" "$GLOBAL_CONFIG"
            updated=true
        fi

        # mcp, permission, skills from repo
        for section in mcp permission skills; do
            repo_val
            repo_val=$(jq ".${section} // empty" "$REPO_CONFIG" 2>/dev/null)
            if [ -n "$repo_val" ]; then
                jq ".${section} = ${repo_val}" "$GLOBAL_CONFIG" > "${GLOBAL_CONFIG}.tmp" && mv "${GLOBAL_CONFIG}.tmp" "$GLOBAL_CONFIG"
                updated=true
            fi
        done

        if [ "$updated" = true ]; then
            ok "Global config synced from repo (default_agent + mcp + permission + skills)"
        else
            skip "Global config already up to date"
        fi
    else
        warn "jq not found — cannot auto-sync opencode.json. Install jq or sync manually."
        warn "  cp ${REPO_CONFIG} ${GLOBAL_CONFIG}"
    fi
else
    warn "Global or repo config not found — sync manually"
fi

# ── Step 5: Global skill config (symlinks) ──────────────────────────
info "Setting up global skill config"
SKILL_DEST="${HOME}/.config/opencode/skills"
SKILL_SRC="${REPO_DIR}/.agents/skills"

if [ ! -d "$SKILL_DEST" ]; then
    mkdir -p "$SKILL_DEST"
fi

# Remove broken symlinks first
for d in "$SKILL_DEST"/*/; do
    [ -L "$d" ] && [ ! -e "$d" ] && rm "$d" && warn "  Removed broken link: $(basename "$d")"
done

# Create symlinks for each skill
if [ ! -L "${SKILL_DEST}/_shared" ]; then
    ln -s "$SKILL_SRC"/*/ "$SKILL_DEST"/ 2>/dev/null || {
        # Fallback: symlink one by one
        for skill_dir in "$SKILL_SRC"/*/; do
            [ -d "$skill_dir" ] || continue
            name="$(basename "$skill_dir")"
            [ -L "${SKILL_DEST}/${name}" ] && continue
            ln -s "$skill_dir" "${SKILL_DEST}/${name}" 2>/dev/null || cp -r "$skill_dir" "${SKILL_DEST}/${name}"
        done
    }
    ok "Skills symlinked to ${SKILL_DEST}"
else
    skip "Skills already configured"
fi

# ── Step 6: Global prompts symlink ────────────────────────────────
# The global config may contain {file:prompts/sdd/*.md} references from agent
# definitions synced in Step 4. Those resolve relative to the global config dir,
# so we need the prompts directory there too.
info "Setting up global prompts symlink"
GLOBAL_PROMPTS_DIR="${HOME}/.config/opencode/prompts"
REPO_SDD_DIR="${REPO_DIR}/prompts/sdd"
SDD_LINK="${GLOBAL_PROMPTS_DIR}/sdd"

if [ -d "$REPO_SDD_DIR" ]; then
    if [ ! -e "$SDD_LINK" ]; then
        mkdir -p "$GLOBAL_PROMPTS_DIR"
        ln -s "$REPO_SDD_DIR" "$SDD_LINK" 2>/dev/null || cp -r "$REPO_SDD_DIR" "$SDD_LINK"
        ok "Prompts symlink created at ${SDD_LINK}"
    else
        skip "Prompts symlink already exists"
    fi
else
    warn "Repo prompts/sdd not found at ${REPO_SDD_DIR}"
fi

# ── Step 7: Global AGENTS.md ──────────────────────────────────────
# {file:AGENTS.md} in gentleman-vMK agent prompt resolves relative to global config
info "Copying AGENTS.md to global config"
GLOBAL_AGENTS_MD="${HOME}/.config/opencode/AGENTS.md"
REPO_AGENTS_MD="${REPO_DIR}/AGENTS.md"

if [ -f "$REPO_AGENTS_MD" ]; then
    if [ ! -f "$GLOBAL_AGENTS_MD" ]; then
        cp "$REPO_AGENTS_MD" "$GLOBAL_AGENTS_MD"
        ok "AGENTS.md copied to global config"
    else
        skip "AGENTS.md already exists in global config"
    fi
else
    warn "Repo AGENTS.md not found at ${REPO_AGENTS_MD}"
fi

# ── Step 8: Install MCP server binaries ─────────────────────────
# These binaries back the MCP servers configured in opencode.json.
# Without them, OpenCode can load the config but the MCPs won't start.
info "Installing MCP server binaries"

# 8a. codebase-memory-mcp — npm global
if command -v codebase-memory-mcp &>/dev/null; then
    skip "codebase-memory-mcp already installed"
else
    info "Installing codebase-memory-mcp..."
    if npm install -g codebase-memory-mcp --no-fund --no-audit --loglevel error 2>/dev/null; then
        ok "codebase-memory-mcp installed"
    else
        warn "codebase-memory-mcp install failed — run 'npm install -g codebase-memory-mcp' manually"
    fi
fi

# 8b. headroom — pip
if command -v headroom &>/dev/null; then
    skip "headroom already installed"
else
    info "Installing headroom..."
    if pip install headroom-ai -q 2>/dev/null; then
        ok "headroom installed"
    else
        warn "headroom install failed — run 'pip install headroom-ai' manually"
    fi
fi

# 8c. engram — GitHub releases
if command -v engram &>/dev/null; then
    skip "engram already installed"
else
    info "Installing engram from GitHub releases..."
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    case "$os" in
        linux*)  os="linux" ;;
        darwin*) os="darwin" ;;
        *)       os="linux" ;;
    esac
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)            arch="amd64" ;;
    esac
    ext="tar.gz"

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT

    # Get latest version from GitHub API
    latest=$(curl -s "https://api.github.com/repos/Gentleman-Programming/engram/releases/latest" 2>/dev/null)
    if [ -z "$latest" ]; then
        warn "engram: Could not fetch release info — download manually from https://github.com/Gentleman-Programming/engram/releases"
    else
        version=$(echo "$latest" | grep -o '"tag_name":\s*"[^"]*"' | cut -d'"' -f4 | sed 's/^v//')
        url="https://github.com/Gentleman-Programming/engram/releases/download/v${version}/engram_${version}_${os}_${arch}.${ext}"

        if curl -sL "$url" -o "${tmp_dir}/engram.${ext}" 2>/dev/null; then
            tar -xzf "${tmp_dir}/engram.${ext}" -C "$tmp_dir" 2>/dev/null

            # Find the binary
            engram_bin=$(find "$tmp_dir" -name "engram" -type f 2>/dev/null | head -1)
            if [ -n "$engram_bin" ]; then
                bin_dir="${HOME}/.local/bin"
                mkdir -p "$bin_dir"
                cp "$engram_bin" "${bin_dir}/engram"
                chmod +x "${bin_dir}/engram"
                ok "engram v${version} installed"
            else
                warn "engram: Binary not found in archive"
            fi
        else
            warn "engram: Download failed — download manually from https://github.com/Gentleman-Programming/engram/releases"
        fi
    fi

    rm -rf "$tmp_dir"
    trap - EXIT
fi

# ── Step 9: Verify ──────────────────────────────────────────────────
info "Verifying setup"
all_ok=true

if [ "${GENTLEMAN_AGENT_ROOT:-}" = "$REPO_DIR" ]; then
    ok "GENTLEMAN_AGENT_ROOT"
else
    warn "GENTLEMAN_AGENT_ROOT — not set in current shell (run 'source ~/.bashrc')"
    all_ok=false
fi

if [ -f "${REPO_DIR}/opencode.json" ]; then
    ok "opencode.json exists"
else
    warn "opencode.json — missing"
    all_ok=false
fi

if command -v gentleman-vmk &>/dev/null; then
    ok "Global shortcut: gentleman-vmk"
else
    warn "Global shortcut: gentleman-vmk — not in PATH"
    all_ok=false
fi

echo ""
if [ "$all_ok" = true ]; then
    printf '%s✅ Machine setup COMPLETE%s\n' "$GREEN" "$NC"
    printf "   %s→ Run 'gentleman-vmk' to launch%s\n" "$CYAN" "$NC"
else
    printf '%s⚠️  Setup PARTIAL — review warnings above%s\n' "$YELLOW" "$NC"
fi
