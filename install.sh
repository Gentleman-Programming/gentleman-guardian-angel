#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - Installer
# ============================================================================
# Installs the gga CLI tool to your system
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# OS detection
detect_os() {
  case "$(uname -s)" in
    Darwin*)          echo "macos" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)                echo "linux" ;;
  esac
}
GGA_OS=$(detect_os)

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}  Gentleman Guardian Angel - Installer${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine install location
if [[ "$GGA_OS" == "windows" ]]; then
    INSTALL_DIR="$HOME/bin"
    mkdir -p "$INSTALL_DIR"
elif [[ -w "/usr/local/bin" ]]; then
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
    if [[ -t 0 ]]; then
        echo -e "${YELLOW}⚠️  gga is already installed${NC}"
        read -p "Reinstall? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Aborted."
            exit 0
        fi
    else
        echo -e "${YELLOW}⚠️  gga is already installed, reinstalling...${NC}"
    fi
fi

# Create lib directory
if [[ "$GGA_OS" == "windows" ]]; then
    LIB_INSTALL_DIR="$HOME/bin/lib/gga"
else
    LIB_INSTALL_DIR="$HOME/.local/share/gga/lib"
fi
mkdir -p "$LIB_INSTALL_DIR"

# Copy files
cp "$SCRIPT_DIR/bin/gga" "$INSTALL_DIR/gga"
cp "$SCRIPT_DIR/lib/providers.sh" "$LIB_INSTALL_DIR/providers.sh"
cp "$SCRIPT_DIR/lib/cache.sh" "$LIB_INSTALL_DIR/cache.sh"
cp "$SCRIPT_DIR/lib/pr_mode.sh" "$LIB_INSTALL_DIR/pr_mode.sh"

# Update LIB_DIR path in installed script
if [[ "$GGA_OS" == "macos" ]]; then
  sed -i '' "s|LIB_DIR=.*|LIB_DIR=\"$LIB_INSTALL_DIR\"|" "$INSTALL_DIR/gga"
else
  sed -i "s|LIB_DIR=.*|LIB_DIR=\"$LIB_INSTALL_DIR\"|" "$INSTALL_DIR/gga"
fi

# Make executable
chmod +x "$INSTALL_DIR/gga"
chmod +x "$LIB_INSTALL_DIR/providers.sh"
chmod +x "$LIB_INSTALL_DIR/cache.sh"

echo -e "${GREEN}✅ Installed gga to $INSTALL_DIR${NC}"
echo ""

# Check if install dir is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo -e "${YELLOW}⚠️  $INSTALL_DIR is not in your PATH${NC}"
  echo ""
  if [[ "$GGA_OS" == "windows" ]]; then
    echo "Add this line to your ~/.bashrc:"
    echo ""
    echo -e "  ${CYAN}export PATH=\"\$HOME/bin:\$PATH\"${NC}"
  else
    echo "Add this line to your ~/.bashrc or ~/.zshrc:"
    echo ""
    echo -e "  ${CYAN}export PATH=\"$INSTALL_DIR:\$PATH\"${NC}"
  fi
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
