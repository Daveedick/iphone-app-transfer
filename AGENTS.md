# iPhone App Transfer: instructions for implementation

Read `README.md`, `PRODUCT.md`, `DESIGN.md`, `docs/ARCHITECTURE.md`, `research/FINDINGS.md`, and `IMPLEMENTATION_PLAN.md` before changing application code. Update `STATUS.md` after meaningful milestones.

The concept and the frosted-glass prototype are approved. Do not restart product discovery, replace the layout, introduce permanent source/target roles, or remove multi-device support. Latest written requirements override prototype omissions: library deletion is mandatory, device uninstall is optional, transient overlays dismiss on outside interaction and app deactivation.

The native MVP already exists. Start with current `STATUS.md` and `docs/QA.md`; do not recreate completed stages from the original handoff. The approved current delivery is display-name renaming to iPhone App Transfer, build 0.1.4 (5), source commit/push to `Daveedick/iphone-app-transfer` and prerelease 0.1.4 with the DMG/checksum. The user subsequently explicitly authorized making this repository public immediately; that later instruction overrides the original private-delivery plan. Before repeating delivery, inspect actual GitHub/local state. Public visibility is authorized; verify unauthenticated access without claiming the pending live tests or project license are complete. This approval does not authorize installing/removing arbitrary real phone apps or modifying macOS security settings.

For the account-clarification update 0.1.5 (6), the user has approved the local app and authorized commit/push. Deliver the verified sources through the existing terminal GitHub authorization. The user separately asked what publishing means; v0.1.5 release assets have not yet been published. The existing public v0.1.4 download remains available.

Keep compatibility identifiers unchanged during branding edits: Bundle ID `app.apptransfer.desktop`, Swift modules/executable `AppTransfer`/`AppTransferCore`, Keychain service `com.apptransfer.AppStoreBridge.v1`, preferences suite `com.apptransfer.AppTransfer`, `~/Library/Application Support/AppTransfer`, and `~/Library/Caches/App Transfer`. Rename visible UI, bundle display name, installer and current docs. Preserve historical artifact names/checksums/screenshots as dated evidence.

Architecture: SwiftUI/AppKit macOS app, direct libimobiledevice through a narrow C bridge, one bundled Go helper using pinned ipatool core. No iMazing dependency, no shell-output parsing as production IPC, no backend server. Do not silently switch to Electron or a web view wrapping the prototype.

Minimum target: macOS 15, Apple Silicon. The development machine currently has Swift 6.0.3 Command Line Tools; full Xcode is not selected. Prefer a reproducible SwiftPM build and app-bundling scripts; verify the toolchain before assuming newer SDK APIs exist. Newer materials/API must have a macOS 15 fallback.

Keep real credentials, cookies, IPA files, phone inventory/UDIDs, raw account metadata, signing material, and private logs out of source control. Use synthetic fixtures. Email may be visible in the user's local UI/logs; never log passwords, OTPs, tokens, or signed URLs.

Never mark an app downloadable solely because it is listed on a device. Never mark installed/launchable based solely on a successful command exit. Read back device state and report activation/login separately.

Do not remove an app or placeholder to repair an install failure automatically. Preserve local phone data. Live mutation tests must use an authorized, specifically identified device/app; ask only if that authorization or identification is missing, and honor permissions already given in the session. A missing phone or login blocks only its live check, not independent implementation work.

Use the mock service only for tests/previews or explicit demo mode. Production failure must never silently fall back to fake success.

Use bounded, meaningful verification. Test account isolation, archive validation, task recovery, deletion safety, packaging, and visual/keyboard behavior. No endless UI polishing after accepted checks.

Browse primary sources for changing Apple/library behavior. Pin versions and record checksums/licenses. Do not infer source provenance from the `ipatool-main` download directory name.

Do not create goals, other user-visible threads, or schedule work unless explicitly requested. Honor the current public-delivery authorization above; the original-code license and pending live acceptance checks remain unresolved and must be reported accurately. Do not modify the user's global Gatekeeper configuration.
