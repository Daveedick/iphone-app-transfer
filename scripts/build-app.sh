#!/bin/bash
set -euo pipefail
app_transfer_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$app_transfer_root"
configuration="${CONFIGURATION:-release}"
app_version="${APP_VERSION:-0.1.5}"
build_number="${APP_BUILD:-6}"
source "$app_transfer_root/scripts/go-env.sh"
./scripts/bootstrap-deps.sh
./scripts/swiftpm.sh build -c "$configuration" --arch arm64
binary_directory="$(./scripts/swiftpm.sh build -c "$configuration" --arch arm64 --show-bin-path)"
mkdir -p .build/helpers dist
(
    cd Helpers/AppStoreBridge
    CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 MACOSX_DEPLOYMENT_TARGET=15.0 \
      go build -mod=readonly -trimpath -o "$app_transfer_root/.build/helpers/AppStoreBridge" ./cmd/appstorebridge
)
staging="$(mktemp -d "$app_transfer_root/.build/app-staging.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/iPhone App Transfer.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Frameworks" "$app/Contents/Resources"
cp "$binary_directory/AppTransfer" "$app/Contents/MacOS/AppTransfer"
cp .build/helpers/AppStoreBridge "$app/Contents/Helpers/AppStoreBridge"
chmod 755 "$app/Contents/MacOS/AppTransfer" "$app/Contents/Helpers/AppStoreBridge"
cp -R Sources/AppTransfer/Resources/. "$app/Contents/Resources/"
for resource_bundle in "$binary_directory"/*.bundle; do
    [ -d "$resource_bundle" ] || continue
    cp -R "$resource_bundle" "$app/Contents/Resources/"
done
python3 scripts/make-icon.py "$app/Contents/Resources/AppIcon.icns"
python3 scripts/bundle.py "$app" "$app_version" "$build_number"
python3 scripts/dependencies.py notices "$app/Contents/Resources/Licenses"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
cp vendor/manifest.json "$app/Contents/Resources/dependency-sources.json"

# Sign the nested components first. This is ad-hoc integrity signing, never
# Developer ID/notarization. No entitlements disable library validation globally.
while IFS= read -r -d '' library; do
    codesign --force --sign - --timestamp=none "$library"
done < <(find "$app/Contents/Frameworks" -type f -name '*.dylib' -print0)
codesign --force --sign - --timestamp=none "$app/Contents/Helpers/AppStoreBridge"
codesign --force --sign - --timestamp=none "$app"
./scripts/verify-bundle.sh "$app"
destination="$app_transfer_root/dist/iPhone App Transfer.app"
if [ -e "$destination" ]; then rm -rf "$destination"; fi
mv "$app" "$destination"
printf 'Built %s\n' "$destination"
