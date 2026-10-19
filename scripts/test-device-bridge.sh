#!/bin/bash
set -euo pipefail
app_transfer_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$app_transfer_root"
mkdir -p .build/bridge-tests
flags=(-std=c11 -Wall -Wextra -Werror -I Sources/DeviceBridge/include -I/opt/homebrew/include -I/opt/homebrew/opt/libarchive/include)
libraries=(-L/opt/homebrew/lib -Wl,-rpath,/opt/homebrew/lib -limobiledevice-1.0 -lplist-2.0 -larchive)
clang "${flags[@]}" -fsanitize=address,undefined -g Helpers/DeviceProbe/safety_tests.c "${libraries[@]}" -o .build/bridge-tests/safety-tests
.build/bridge-tests/safety-tests
if [ "${1:-}" = --live-read-only ]; then
    clang "${flags[@]}" Sources/DeviceBridge/device_bridge.c Helpers/DeviceProbe/main.c "${libraries[@]}" -o .build/bridge-tests/device-probe
    .build/bridge-tests/device-probe
elif [ -n "${1:-}" ]; then
    echo 'Usage: test-device-bridge.sh [--live-read-only]' >&2; exit 2
fi
