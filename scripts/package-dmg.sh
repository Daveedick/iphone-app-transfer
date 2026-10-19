#!/bin/bash
set -euo pipefail
app_transfer_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$app_transfer_root"
app="$app_transfer_root/dist/iPhone App Transfer.app"
[ -d "$app" ] || { echo 'Run ./scripts/build-app.sh first.' >&2; exit 1; }
./scripts/verify-bundle.sh "$app"
version="${APP_VERSION:-0.1.5}"
mkdir -p dist
staging="$(mktemp -d "$app_transfer_root/.build/dmg-staging.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/iPhone App Transfer.app"
ln -s /Applications "$staging/Applications"
cat > "$staging/Read Me.txt" <<'EOF'
iPhone App Transfer — preview for Apple Silicon / macOS 15+

Drag iPhone App Transfer to Applications, then open it.
This preview is ad-hoc signed and is not notarized by Apple. If macOS blocks
launch, inspect System Settings > Privacy & Security for Open Anyway.
Do not disable Gatekeeper globally. If macOS reports damage or a broken
signature, obtain a fresh build and verify it rather than disabling protections.

Connect your unlocked iPhones by USB and confirm Trust when prompted.
Use App Store Accounts to sign in directly in the app. Passwords and verification codes
are never requested in a chat. Some authentication components download on first sign-in or download from
their upstream hosts. The app does not require Terminal, Homebrew, Go or iMazing.

Accounts download from Apple's servers. Availability depends on the account's
region, rights to the app and available version. Add other accounts for apps
obtained through them. The app shows the account used for each download.
After installation, open the app on the iPhone. It may request the account that
obtained the IPA; the app shows the known account or marks it as unknown.
Verified installation does not guarantee successful launch or activation.
App data and banking sessions are not transferred. Keep the original phone
and applications until you have opened and checked the new installations.
EOF
output="$app_transfer_root/dist/iPhone-App-Transfer-$version-arm64.dmg"
hdiutil create -volname 'iPhone App Transfer' -srcfolder "$staging" -ov -format UDZO "$output"
hdiutil verify "$output"
(
    cd "$app_transfer_root/dist"
    shasum -a 256 "$(basename "$output")" > "$(basename "$output").sha256"
)
printf 'Packaged %s\n' "$output"
