#!/usr/bin/env bash

# ============================================================================
# Gentleman Guardian Angel - Uninstaller
# ============================================================================
# Removes the gga CLI tool from your system
# ============================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}  Gentleman Guardian Angel - Uninstaller${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Find and remove binary
LOCATIONS=(
  "/usr/local/bin/gga"
  "$HOME/.local/bin/gga"
)

FOUND=false
for loc in "${LOCATIONS[@]}"; do
  if [[ -f "$loc" ]]; then
    rm "$loc"
    echo -e "${GREEN}✅ Removed: $loc${NC}"
    FOUND=true
  fi
done

# Remove lib directory
LIB_DIR="$HOME/.local/share/gga"
if [[ -d "$LIB_DIR" ]]; then
  rm -rf "$LIB_DIR"
  echo -e "${GREEN}✅ Removed: $LIB_DIR${NC}"
  FOUND=true
fi

# Remove global config (optional)
GLOBAL_CONFIG="$HOME/.config/gga"
if [[ -d "$GLOBAL_CONFIG" ]]; then
  echo ""
  read -rp "Remove global config ($GLOBAL_CONFIG)? (y/N): " confirm
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    rm -rf "$GLOBAL_CONFIG"
    echo -e "${GREEN}✅ Removed: $GLOBAL_CONFIG${NC}"
  else
    echo -e "${YELLOW}⚠️  Kept global config${NC}"
  fi
fi

if [[ "$FOUND" == false ]]; then
  echo -e "${YELLOW}⚠️  gga was not found on this system${NC}"
fi

echo ""
echo -e "${BOLD}Note:${NC} Project-specific configs (.gga) and git hooks"
echo "      were not removed. Remove them manually if needed."
echo ""
