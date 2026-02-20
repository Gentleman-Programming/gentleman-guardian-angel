#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - Installer
# ============================================================================
# Installs the gga CLI tool to your system
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}  Gentleman Guardian Angel - Installer${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine install location
if [[ -w "/usr/local/bin" ]]; then
    INSTALL_DIR="/usr/local/bin"
elif [[ -d "$HOME/.local/bin" && -w "$HOME/.local/bin" ]]; then
    INSTALL_DIR="$HOME/.local/bin"
else
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
fi

echo -e "${BLUE}ℹ️  Install directory: $INSTALL_DIR${NC}"
echo ""

if [[ ! -w "$INSTALL_DIR" ]]; then
    echo -e "${RED}❌ No write permission to $INSTALL_DIR${NC}"
    echo -e "${YELLOW}Fix ownership or permissions, e.g.:${NC}"
    echo "  sudo chown -R $USER:$USER $INSTALL_DIR"
    exit 1
fi

# Check if already installed
if [[ -f "$INSTALL_DIR/gga" ]]; then
    echo -e "${YELLOW}⚠️  gga is already installed${NC}"
    read -rp "Reinstall? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Create lib directory
LIB_INSTALL_DIR="$HOME/.local/share/gga/lib"
mkdir -p "$LIB_INSTALL_DIR"

# Copy files
cp "$SCRIPT_DIR/bin/gga" "$INSTALL_DIR/gga"

# Copy ALL lib files (not just providers.sh and cache.sh)
for lib_file in "$SCRIPT_DIR/lib/"*.sh; do
  if [[ -f "$lib_file" ]]; then
    cp "$lib_file" "$LIB_INSTALL_DIR/"
  fi
done

# Update LIB_DIR path in installed script
if [[ "$(uname)" == "Darwin" ]]; then
  sed -i '' "s|LIB_DIR=.*|LIB_DIR=\"$LIB_INSTALL_DIR\"|" "$INSTALL_DIR/gga"
else
  sed -i "s|LIB_DIR=.*|LIB_DIR=\"$LIB_INSTALL_DIR\"|" "$INSTALL_DIR/gga"
fi

# Make executable
chmod +x "$INSTALL_DIR/gga"
chmod +x "$LIB_INSTALL_DIR/"*.sh

echo -e "${GREEN}✅ Installed gga to $INSTALL_DIR${NC}"
echo ""

# Check if install dir is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo -e "${YELLOW}⚠️  $INSTALL_DIR is not in your PATH${NC}"
  echo ""
  echo "Add this line to your ~/.bashrc or ~/.zshrc:"
  echo ""
  echo -e "  ${CYAN}export PATH=\"$INSTALL_DIR:\$PATH\"${NC}"
  echo ""
fi

echo -e "${BOLD}Getting started:${NC}"
echo ""
echo "  1. Navigate to your project:"
echo "     cd /path/to/your/project"
echo ""
echo "  2. Initialize config:"
echo "     gga init"
echo ""
echo "  3. Create your AGENTS.md with coding standards"
echo ""
echo "  4. Install the git hook:"
echo "     gga install"
echo ""
echo "  5. You're ready! The hook will run on each commit."
echo ""
