#!/usr/bin/env bash
# Wrapper for health-check-system.ps1 — cross-platform entry point
# Usage: ./scripts/health-check-system.sh [-Json]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v pwsh &>/dev/null; then
    exec pwsh -NoProfile -File "$SCRIPT_DIR/health-check-system.ps1" "$@"
else
    echo "ERROR: PowerShell 7 (pwsh) is required but not installed."
    echo "Install: https://github.com/PowerShell/PowerShell#get-powershell"
    exit 1
fi
