#!/bin/bash
set -euo pipefail
app_transfer_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$app_transfer_root"
swiftc_path="$(xcrun --find swiftc)"
pm_runtime="$(cd "$(dirname "$swiftc_path")/../lib/swift/pm" && pwd)"
local_pm="$app_transfer_root/.build/toolchain/pm"
mkdir -p "$local_pm/ManifestAPI/PackageDescription.swiftmodule" "$local_pm/ManifestAPI/CompilerPluginSupport.swiftmodule"

# Some CLT installations contain stale private interfaces beside newer public
# interfaces/dylib. Swift prefers the private one and links obsolete symbols.
# Use only matching public interfaces in a project-local runtime; never edit CLT.
cp "$pm_runtime/ManifestAPI/libPackageDescription.dylib" "$local_pm/ManifestAPI/"
for module in PackageDescription CompilerPluginSupport; do
    for interface in "$pm_runtime/ManifestAPI/$module.swiftmodule/"*.swiftinterface; do
        case "$interface" in *.private.swiftinterface) continue ;; esac
        cp "$interface" "$local_pm/ManifestAPI/$module.swiftmodule/"
    done
done
if [ -d "$pm_runtime/PluginAPI" ] && [ ! -e "$local_pm/PluginAPI" ]; then
    ln -s "$pm_runtime/PluginAPI" "$local_pm/PluginAPI"
fi
export SWIFTPM_CUSTOM_LIBS_DIR="$local_pm"
export CLANG_MODULE_CACHE_PATH="$app_transfer_root/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$app_transfer_root/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
swiftpm_command="${1:?Use build, test, or package as the first argument}"
shift
overlay="$(python3 "$app_transfer_root/scripts/prepare-toolchain.py")"
case "$swiftpm_command" in
    build|test|run)
        exec xcrun swift "$swiftpm_command" --disable-sandbox \
          -Xswiftc -vfsoverlay -Xswiftc "$overlay" \
          -Xcc -ivfsoverlay -Xcc "$overlay" "$@" ;;
    *) exec xcrun swift "$swiftpm_command" --disable-sandbox "$@" ;;
esac
