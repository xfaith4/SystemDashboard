#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/Launch.ps1" "$@"
