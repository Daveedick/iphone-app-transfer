#!/bin/bash
set -euo pipefail
app_transfer_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$app_transfer_root"
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    echo 'The MVP build requires Apple Silicon macOS.' >&2; exit 1
fi
for tool in swift clang codesign install_name_tool hdiutil iconutil sips python3; do
    command -v "$tool" >/dev/null || { echo "Missing developer tool: $tool" >&2; exit 1; }
done
command -v go >/dev/null || { echo 'Install Go 1.26 or newer for the developer build.' >&2; exit 1; }
python3 "$app_transfer_root/scripts/dependencies.py" check
printf 'Developer prerequisites verified. Homebrew and Go are not user runtime requirements.\n'
