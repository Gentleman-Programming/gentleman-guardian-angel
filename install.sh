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
  if [[ -n "${GGA_TEST_OS:-}" ]]; then
    echo "$GGA_TEST_OS"
    return 0
  fi

  case "$(uname -s)" in
    Darwin*)          echo "macos" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)                echo "linux" ;;
  esac
}
GGA_OS=$(detect_os)

sed_in_place() {
  local expression="$1"
  local file="$2"

  case "$(uname -s)" in
    Darwin*) sed -i '' "$expression" "$file" ;;
    *)       sed -i "$expression" "$file" ;;
  esac
}

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

if [[ "$GGA_OS" == "windows" ]]; then
  cat > "$INSTALL_DIR/gga.bat" <<'EOF'
@echo off
setlocal

for /f "delims=" %%i in ('where git 2^>nul') do set "GIT_CMD=%%i" & goto :found_git

echo Git not found on PATH. Install Git for Windows to use gga from cmd.exe.
exit /b 1

:found_git
for %%i in ("%GIT_CMD%") do set "GIT_DIR=%%~dpi"
set "BASH_EXE=%GIT_DIR%..\bin\bash.exe"

if not exist "%BASH_EXE%" (
  for /f "delims=" %%j in ('where bash 2^>nul') do set "BASH_EXE=%%j" & goto :found_bash
)

:found_bash
if not exist "%BASH_EXE%" (
  echo Git Bash not found. Install or repair Git for Windows.
  exit /b 1
)

"%BASH_EXE%" "%~dp0gga" %*
exit /b %ERRORLEVEL%
EOF
fi

# Inject version from git tag if available (otherwise stays "dev")
GIT_VERSION=$(cd "$SCRIPT_DIR" && git describe --tags --abbrev=0 2>/dev/null || true)
GIT_VERSION="${GIT_VERSION#v}"  # Strip leading 'v'
if [[ -n "$GIT_VERSION" ]]; then
  sed_in_place "s|VERSION=\"\${GGA_VERSION:-dev}\"|VERSION=\"$GIT_VERSION\"|" "$INSTALL_DIR/gga"
fi

# Update LIB_DIR path in installed script
sed_in_place "s|LIB_DIR=.*|LIB_DIR=\"$LIB_INSTALL_DIR\"|" "$INSTALL_DIR/gga"

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
    echo "For Git Bash, add this line to your ~/.bashrc:"
    echo ""
    echo -e "  ${CYAN}export PATH=\"\$HOME/bin:\$PATH\"${NC}"
    echo ""
    echo "For cmd.exe or PowerShell, add this directory to your Windows user PATH:"
    echo ""
    printf '  %b%s%b\n' "$CYAN" '%USERPROFILE%\bin' "$NC"
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
