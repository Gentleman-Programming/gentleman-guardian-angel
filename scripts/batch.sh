#!/usr/bin/env bash
# Wrapper for batch.ps1 — cross-platform entry point
# Usage: ./scripts/batch.sh [options]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v pwsh &>/dev/null; then
    exec pwsh -NoProfile -File "$SCRIPT_DIR/batch.ps1" "$@"
else
    echo "ERROR: PowerShell 7 (pwsh) is required but not installed."
    echo "Install: https://github.com/PowerShell/PowerShell#get-powershell"
    exit 1
fi
