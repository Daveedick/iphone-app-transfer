# iPhone App Transfer — developer build

Target: Apple Silicon, macOS 15+. End users receive one app/DMG and do not need
these developer dependencies. Build prerequisites: Swift/Clang CLT or Xcode,
Go 1.26+, Python 3, and the pinned native libraries/headers described by
`vendor/manifest.json`. Native developer inputs are checked, never upgraded
automatically. Source URLs and hashes permit reconstructing those versions;
Homebrew's existing bottles were used for this local preview.

```sh
./scripts/bootstrap-deps.sh
./scripts/test-core.sh
./scripts/test-device-bridge.sh
./scripts/build-app.sh
./scripts/package-dmg.sh
./scripts/verify-bundle.sh 'dist/iPhone App Transfer.app'
```

`CONFIGURATION=debug` selects a debug Swift build. `APP_VERSION` and `APP_BUILD`
control bundle metadata (defaults 0.1.5/6). Outputs are `dist/iPhone App Transfer.app`,
`dist/iPhone-App-Transfer-0.1.5-arm64.dmg` and a SHA-256 file. The local account-clarification update has been approved for source delivery; the public DMG remains v0.1.4 until a new GitHub release is published. The product display name changed in 0.1.4; the internal executable/module is still `AppTransfer`. Bundle ID, Keychain service, preferences, local library and the `~/Library/Caches/App Transfer` runtime cache retain their existing identifiers so users keep saved state. No command publishes,
installs onto phones, removes phone apps, or changes Gatekeeper settings.

`test-core.sh` is the portable CLT runner for the same Core/Coordinator test
sources. On a full Xcode setup that provides XCTest, `./scripts/swiftpm.sh test`
is also available. CLT alone does not include the XCTest framework; a missing
XCTest module is not a failed application/domain test.

`swiftpm.sh` isolates a known CLT 6.0.3 inconsistency: the system directory has
December 2024 public PackageDescription interfaces/dylib beside stale February
2024 private interfaces. Swift selects obsolete symbols and fails to link a
manifest. The wrapper copies only public interfaces plus the matching library
into `.build/toolchain/pm`, using the supported `SWIFTPM_CUSTOM_LIBS_DIR` override.
It changes no system file. This can also be used with an otherwise healthy CLT.
[SwiftPM override documentation](https://github.com/swiftlang/swift-package-manager/blob/main/CONTRIBUTING.md#overriding-the-path-to-the-runtime-libraries).

This CLT also contains two equivalent SwiftBridging module maps, causing Clang
module redefinition and misleading SDK mismatch errors. `prepare-toolchain.py`
hides only the obsolete duplicate through a project-local VFS overlay after
confirming the maps have identical declarations. Both Swift and Clang receive
the overlay, including implicit SDK module compilation. No SDK/header is edited.
Module caches are inside `.build`. SwiftPM's child build sandbox is disabled to
allow builds inside an already sandboxed agent; macOS security settings are not
changed. For the current prepopulated Go build cache, set
`APP_TRANSFER_GO_ROOT=/private/tmp/app-transfer-go`; default is `.build/go`.

`bundle.py` follows the actual Mach-O dependency graph, copies third-party dylibs,
rewrites their names to relative bundle paths, removes developer rpaths and checks
arm64/macOS minimums. Original input hashes accompany the bundle. The script
does not strip signatures from Apple's system libraries or ship system runtimes.
Nested libraries/helper are ad-hoc signed before the containing app.

`Contents/Resources/build-information.json` records an aggregate SHA-256 of the
runtime source/build inputs. Compare it with `python3 scripts/bundle.py
--source-digest` to determine whether a later source fix requires rebuilding.

These static/linkage checks establish packaging integrity. They do **not** prove
clean-user login, a clean Mac without Homebrew, real iOS installation, launch of
downloaded apps, or the quarantined DMG Gatekeeper experience. Record those live
checks separately in `docs/ACCEPTANCE.md`; do not relabel a preview a tested release.

`test-device-bridge.sh` runs focused archive/options/terminal-status/argument
safety tests under AddressSanitizer and UndefinedBehaviorSanitizer without any
phone communication. `--live-read-only` additionally enumerates USB phones,
checks metadata/readback/icons and subscription cleanup. It never installs or
removes apps, resets pairing or writes raw inventory.
