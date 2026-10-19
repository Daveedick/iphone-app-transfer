#!/bin/bash
set -euo pipefail
app_transfer_root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-$app_transfer_root/dist/iPhone App Transfer.app}"
codesign --verify --deep --strict --verbose=2 "$app"
python3 "$app_transfer_root/scripts/bundle.py" --verify "$app"
printf 'Bundle integrity, arm64/minimum-OS and dependency closure verified.\n'
