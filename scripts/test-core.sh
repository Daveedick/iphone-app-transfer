#!/bin/bash
# Execute the shared test bodies on macOS CLT without an XCTest installation.
# This builds production Core/Archive code plus an explicitly portable assertion
# adapter; it is not a substitute label for an XCTest run.
set -euo pipefail
app_transfer_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$app_transfer_root"
portable_root="$app_transfer_root/.build/portable-tests"
mkdir -p "$portable_root/Modules" "$portable_root/module-cache"
export CLANG_MODULE_CACHE_PATH="$portable_root/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$portable_root/module-cache"
sdk="$(xcrun --show-sdk-path)"
swiftc_path="$(xcrun --find swiftc)"

# The CLT installation may contain a duplicate old SwiftBridging module map.
# Create the same narrow, local VFS adjustment as prepare-toolchain.py, with all
# outputs isolated from SwiftPM builds and without changing the installed CLT.
python3 - "$portable_root" "$swiftc_path" <<'PY'
from pathlib import Path
import json,re,sys
out=Path(sys.argv[1]);headers=Path(sys.argv[2]).parent.parent/'include/swift'
old=headers/'module.modulemap';current=headers/'bridging.modulemap'
empty=out/'empty-module.modulemap';empty.write_text('// Portable test build: hide identical obsolete SwiftBridging map.\n')
roots=[]
def body(p):return re.sub(r'\s+','',re.sub(r'//[^\n]*','',p.read_text()))
if old.is_file() and current.is_file() and body(old)==body(current) and 'moduleSwiftBridging{' in body(old):
 roots=[{'type':'file','name':str(old),'external-contents':str(empty)}]
(out/'swift-overlay.json').write_text(json.dumps({'version':0,'roots':roots}))
PY
common=(-sdk "$sdk" -target arm64-apple-macosx15.0 -swift-version 5
  -module-cache-path "$portable_root/module-cache"
  -vfsoverlay "$portable_root/swift-overlay.json"
  -Xcc -ivfsoverlay -Xcc "$portable_root/swift-overlay.json")
cat > "$portable_root/ArchiveBridge.modulemap" <<MAP
module ArchiveBridge {
  umbrella header "$app_transfer_root/Sources/ArchiveBridge/include/ArchiveBridge.h"
  export *
}
MAP
xcrun clang -arch arm64 -isysroot "$sdk" -mmacosx-version-min=15.0 \
  -I Sources/ArchiveBridge/include -I "${APPTRANSFER_ARCHIVE_INCLUDE:-/opt/homebrew/opt/libarchive/include}" -c Sources/ArchiveBridge/archive_bridge.c \
  -o "$portable_root/ArchiveBridge.o"
"$swiftc_path" "${common[@]}" -parse-as-library -whole-module-optimization \
  -emit-module -emit-object -module-name PortableTestSupport \
  -emit-module-path "$portable_root/Modules/PortableTestSupport.swiftmodule" \
  Tests/PortableTestSupport/Assertions.swift -o "$portable_root/PortableTestSupport.o"
"$swiftc_path" "${common[@]}" -parse-as-library -whole-module-optimization -enable-testing \
  -emit-module -emit-object -module-name AppTransferCore \
  -emit-module-path "$portable_root/Modules/AppTransferCore.swiftmodule" \
  -Xcc "-fmodule-map-file=$portable_root/ArchiveBridge.modulemap" \
  Sources/AppTransferCore/*.swift -o "$portable_root/AppTransferCore.o"

# Register every zero-argument test method from the shared source files, so a new
# test cannot silently disappear because somebody forgot a hand-written list.
python3 - "$portable_root" <<'PY'
from pathlib import Path
import re,sys
out=Path(sys.argv[1]);calls=[]
for path in sorted(Path('Tests/AppTransferCoreTests').glob('*.swift')):
 source=path.read_text()
 classes=re.findall(r'final\s+class\s+(\w+)\s*:\s*XCTestCase',source)
 methods=re.findall(r'func\s+(test\w+)\s*\(\s*\)\s*(async\s*)?(throws\s*)?\{',source)
 declared=re.findall(r'\bfunc\s+(test\w+)\s*\(',source)
 if sorted(declared)!=sorted(method[0] for method in methods):raise SystemExit(f'Unsupported test signature; refusing to skip a test in {path}')
 if not methods:continue
 if len(classes)!=1:raise SystemExit(f'Cannot safely register test classes in {path}')
 name=classes[0]
 for method,asynchronous,throwing in methods:
  invocation=('try ' if throwing else '')+('await ' if asynchronous else '')+f'instance.{method}()'
  calls.append(f'        await PortableRunner.execute("{name}.{method}", instance: {name}()) {{ instance in {invocation} }}')
if not calls:raise SystemExit('No portable tests found')
(out/'RegisteredTests.swift').write_text('enum RegisteredTests {\n    static let count = '+str(len(calls))+'\n    static func runAll() async {\n'+'\n'.join(calls)+'\n    }\n}\n')
PY
"$swiftc_path" "${common[@]}" -parse-as-library -DAPPTRANSFER_PORTABLE_TESTS \
  -I "$portable_root/Modules" -Xcc "-fmodule-map-file=$portable_root/ArchiveBridge.modulemap" \
  Tests/AppTransferCoreTests/*.swift Tests/PortableRunner/Runner.swift "$portable_root/RegisteredTests.swift" \
  "$portable_root/PortableTestSupport.o" "$portable_root/AppTransferCore.o" "$portable_root/ArchiveBridge.o" \
  -larchive -o "$portable_root/core-tests" | tee "$portable_root/results.log"

set +e
"$portable_root/core-tests" --self-check-failure > "$portable_root/negative-self-check.log" 2>&1
negative_status=$?
set -e
if [ "$negative_status" -ne 1 ]; then
  cat "$portable_root/negative-self-check.log"
  echo "Portable harness failed its negative assertion/async teardown self-check (status $negative_status)." >&2
  exit 1
fi
echo "Portable harness negative assertion + async teardown self-check passed."
"$portable_root/core-tests" | tee "$portable_root/results.log"
