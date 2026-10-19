# iPhone App Transfer

**English** · [Русский](README.ru.md)

A native macOS utility for moving eligible iPhone apps through a local IPA library. Connect your phones, see their apps side by side, download an available archive from Apple, and queue installation on another phone. Devices have equal roles, with no permanent source/target selection or two-phone limit.

**Apple Silicon · macOS 15+ · 0.1.4 public preview.** Device discovery, fresh GUI Apple Account sign-in, a real download, library reuse, and local packaging have been verified. The new app's complete installation/readback/launch flow on a second iPhone remains pending. Availability and successful launch are not guaranteed for every app.

The account explanations described below are the **0.1.5 (6) update**, approved locally for source delivery. Its DMG release has not yet been published. The public download remains v0.1.4; current verification is recorded in [QA](docs/QA.md) and [status](STATUS.md).

## Contents

- [What it does](#what-it-does)
- [Install](#install)
- [Connect your iPhones](#connect-your-iphones)
- [Accounts and licenses](#accounts-and-licenses)
- [Download and transfer](#download-and-transfer)
- [Versions and availability](#versions-and-availability)
- [Queue and activity](#queue-and-activity)
- [Import and delete](#import-and-delete)
- [Settings and shortcuts](#settings-and-shortcuts)
- [Privacy and storage](#privacy-and-storage)
- [Troubleshooting](#troubleshooting)
- [Validation and limits](#validation-and-limits)
- [Build and contribute](#build-and-contribute)
- [Licenses](#licenses)

## What it does

iPhone App Transfer combines USB-connected iPhone app lists, a shared library of IPA archives, and a persistent download/installation queue. Device columns scroll horizontally when necessary, with quick navigation and independent searches.

An app on a phone supplies identifiers and version metadata. iPhone App Transfer obtains its archive from Apple using an eligible Apple Account, or reuses an IPA in your library. **It does not extract the installed binary from the old iPhone.** A visible app is not proof that Apple will still supply it.

Local app data, banking sessions, passwords, and in-app sign-ins are outside the scope. After installation, sign in to the app again; its own cloud data is handled by that service. TestFlight downloads and removal of phone apps are not offered in this preview.

## Install

Get the DMG and accompanying SHA-256 file from the [public preview v0.1.4 release](https://github.com/Daveedick/iphone-app-transfer/releases/tag/v0.1.4). The repository and release downloads are publicly accessible; no repository invitation is needed. **Code → Download ZIP** supplies source code, not an installer. The next local review outputs are `dist/iPhone-App-Transfer-0.1.5-arm64.dmg` and `dist/iPhone App Transfer.app`; v0.1.5 is not yet published.

Open the DMG, drag **iPhone App Transfer** into **Applications**, and launch that copy. The packaged app includes its helper and native libraries. End users do not need Terminal, Homebrew, Go, iMazing, or a separate ipatool installation.

The preview has an **ad-hoc integrity signature**, without Developer ID or Apple notarization. If macOS blocks an unidentified developer, review the download source and use the individual app's **System Settings → Privacy & Security → Open Anyway** option when offered. Do not globally disable Gatekeeper. Investigate damaged-app or invalid-signature errors rather than bypassing integrity checks. The downloaded/quarantined DMG experience on a clean Mac remains unverified.

Downloads require internet access and Mac storage; installation also needs space on the destination iPhone. First sign-in or download may take longer while authentication components are prepared. When updating, finish active work and quit the old app before replacing its copy in Applications. The previous product was named **App Transfer**; keep only the current app copy in Applications. The rename retains the existing storage identifiers described below to preserve compatibility. macOS may request Keychain access again after the helper changes; review that system prompt when opening the updated app.

## Connect your iPhones

1. Connect a phone with a data-capable USB cable.
2. Unlock it with its passcode and accept **Trust This Computer** if prompted.
3. Let iPhone App Transfer load the app list. Use **Refresh Devices** if needed.
4. Connect additional phones in the same way. Check each column's name, model, iOS version, and connection state before selecting a destination.

One phone is enough to inspect apps and populate the library; a destination can be connected later. Use the navigation strip or horizontal scrolling for additional device columns.

An **offloaded** app is a placeholder without its installed executable. Metadata can identify a possible download, but the phone cannot supply its IPA. Locked, disconnected, or untrusted phones produce an appropriate task state instead of a successful transfer.

## Accounts and licenses

Open **App Store Accounts**, enter the Apple Account email and password, and complete the verification-code prompt if Apple requests one. Enter credentials only in the app's secure form. Authentication preparation may show an indeterminate progress message.

These accounts download IPA files from Apple's servers. Availability depends on the account's region, rights to the app, and whether Apple supplies the requested version. The tool is not an independent archive of every app and does not bypass regional availability or acquire licenses automatically. Apps installed by a bank or service center can belong to an inaccessible account.

Add other accounts when different apps were obtained through them: purchase histories and regions can differ. Each account has a separate session; live second-account behavior still requires verification.

Before a download, the selection details show **Download through: email** and the reason. An authenticated account matching the owner hint from phone metadata is preferred; otherwise the authenticated **Default** account or the sole available account is used. The hint is not a license check. **Choose Account** on a task makes an explicit choice that stays with that task; changing the default does not change queued tasks. The queue, including the active collapsed summary, shows the account actually used. An authenticated badge means a saved session exists; Apple can still reject or expire it.

There are **two separate sign-ins**:

- **Apple Account:** permits downloading an entitled IPA and may be required by iOS when launching it. The iPhone hint is based on the IPA actually used, which can differ from the source phone's account hint. Signing in to iPhone App Transfer does not change the phone's primary Apple Account or transfer an entitlement to a different account.
- **Bank/app/service account:** signs you into the installed app afterward. Its session and local data are not copied by iPhone App Transfer.

Use **Sign in again** for an expired session. A waiting task offers account selection. Closing App Store Accounts dismisses the panel without canceling authentication or background work; use **Cancel sign-in** when cancellation is intended.

## Download and transfer

| Drag direction | Result |
| --- | --- |
| Phone → Library | Download and validate an IPA, or reuse a matching saved archive; no installation. |
| Phone → another phone | Reuse/download the required IPA, then queue installation on that destination. |
| Library → phone | Queue installation of the saved IPA. |

Context menus and the selection action bar provide the same actions. Command-click selects multiple items; Shift selects a range.

Start with an app on the phone and choose **Save to Library**. Follow its task until download/validation completes. Repeating an eligible request can reuse the archive instead of creating another copy.

To install, connect the destination and drag a library entry to its column. iPhone App Transfer checks the target and archive, uploads it, requests installation, then reads back the expected app identity/version before reporting success. An app already installed on the target is skipped; automatic replacement/downgrade is not provided. The library copy remains reusable.

After verified installation, **open the app on the iPhone**. The result identifies the account that may be required from the actual IPA's known information, or marks it unknown. If a source app mentions account A but the downloaded IPA belongs to B, the iPhone hint uses B. Conflicting account information remains explicit. Verified installation does not guarantee launch, a one-time-only login, or future updates: Apple Account activation, compatibility, or the service itself may still prevent use. The complete installation path remains a pending live check in this preview. Installing a saved IPA does not itself require signing in again on the Mac.

## Versions and availability

iPhone App Transfer first attempts the version identified on the source phone. If that version is unavailable and Apple supplies a latest-version candidate, it shows the difference and asks for explicit confirmation. This is not a browser for every historical version, and the latest version is never silently substituted.

Removed apps, unavailable older releases, regional restrictions, missing entitlements, incomplete metadata, and TestFlight versions can block downloads. Neither a visible icon nor a store identifier guarantees that a removed App Store app can be recovered.

Before an archive enters the library, validation checks ZIP integrity and unsafe paths, reads app metadata, and calculates SHA-256. For a download, identity/version/build are compared with independently expected values when those are known. For an imported IPA, the app reads the archive metadata without an independently established expected identity; import is not an authenticity check. Presence of a signature-related file does not prove a valid license or guaranteed activation. Account/build variants remain distinct; one account's archive is not treated as another account's entitlement.

## Queue and activity

New or retried tasks appear at the top, briefly highlighted with a confirmation. A collapsed queue acknowledges additions in its header. Repeating an active request points to its existing task.

**Display order differs from execution order.** One ready task executes at a time in stored queue order; a task waiting for an account or device can leave independent ready work available. Retry changes visual recency without making execution newest-first.

Drag the full-width divider above the queue to resize it. The focused divider also supports ↑/↓. Height survives collapse and restart; smaller windows preserve room for app rows.

Stages distinguish waiting, download, validation, upload, installation, verification, completion, skip, cancellation, and failure. Percentages appear only when measured. **Pause** stops subsequent work after the current operation. Cancellation during installation/verification lets the device finish that operation before the queue stops; it does not promise an instant interruption of iOS.

After disconnection, reconnect the same phone and choose **Retry**. Interrupted operations after restart require review/retry rather than being declared successful. **Activity** records operations and recovery messages locally.

Tasks and Activity preserve the known account details of the IPA actually used, so removing a saved authorization or library entry does not erase that historical explanation. The download account and any account inferred only from archive metadata remain distinguishable.

## Import and delete

**Import IPA…** (`⌘O`) copies and validates an existing IPA into the library. The original stays in place. An imported entry is not automatically bound to a saved Apple Account (`accountID` is unknown). Import does not grant a license or guarantee installation/activation.

Library details label a confirmed app download **Downloaded through: email**. Imported archives are labeled **Imported IPA** and may show **Account from IPA metadata: email**. Metadata does not prove who downloaded the file or holds its license. Older records without a confirmed download account retain this uncertainty rather than treating a metadata email as a proven downloader.

Select library items and choose **Delete from Library…**, the context-menu action, or `⌘⌫`. Confirmed deletion moves the managed IPA to the **Mac's Trash**, preserving imported originals and phone apps. Unfinished tasks protect archives they need; cancel waiting tasks or finish work before deleting them.

Phone app removal is not exposed. Failed installations never trigger automatic deletion of existing apps or placeholders.

## Settings and shortcuts

Settings provides Russian/English, compact/comfortable density, and system/light/dark appearance. Compact is the default. Preferences apply immediately and persist. Settings/Accounts close on outside interaction, app deactivation, Escape, or opening the other panel.

| Shortcut | Action |
| --- | --- |
| `⌘S` | Show/hide Library |
| `⌘J` | Show/hide Queue |
| `⌘O` | Import IPA |
| `⌘R` | Refresh devices |
| `⌘,` | Settings |
| `⌘⌫` | Request confirmed deletion of selected library items |
| Command/Shift + selection | Multiple/range selection |
| Arrow keys | Navigate a focused list; resize a focused queue divider |
| Escape | Dismiss Settings/Accounts |

## Privacy and storage

There is no iPhone App Transfer backend. Apple requests run from the Mac. Authorization uses a separate namespace, without importing iMazing or standalone ipatool account state.

| Data | Storage |
| --- | --- |
| Account registry and emails, saved session credentials, cookie records, authentication state | Account-scoped macOS Keychain entries under `com.apptransfer.AppStoreBridge.v1` |
| Password/verification code | Transient sign-in input; not persisted by the helper or written to activity |
| IPA files, icons, manifest, queue, activity | `~/Library/Application Support/AppTransfer` |
| Interface preferences | macOS user preferences |
| Authentication runtime/assets | Dedicated `~/Library/Caches/App Transfer` namespace |

The product rename keeps Bundle ID `app.apptransfer.desktop`, Keychain service `com.apptransfer.AppStoreBridge.v1`, preferences suite `com.apptransfer.AppTransfer`, and the storage paths above stable for compatibility. These internal names are not separate installations or third-party caches.

Support directories use owner-only access; saved JSON uses owner-only permissions. This is access control, not a claim that all disk data is encrypted. Library/history may contain full account emails, app identities, device names/identifiers, and destination references. Review records and screenshots before sharing. Activity excludes passwords, OTPs, tokens, and signed download URLs.

The first authorized login or download may fetch pinned, checksum-verified Apple SAP components from Apple software-distribution servers and Unicorn runtime assets from PyPI. They are not embedded in the DMG; clean first-run preparation remains to be validated.

**Remove authorization** deletes the account's local auth entries and registry record. It preserves IPA files, ownership references, activity, installed phone apps, and the Apple Account itself. Re-adding the same email creates a new internal account UUID; it does not automatically rebind old library entries or queued work. Removing the `.app` alone does not erase all local data.

## Troubleshooting

| Symptom | Next step |
| --- | --- |
| Phone missing/locked/trust required | Check the USB data connection, unlock with the passcode, accept Trust, refresh. |
| Account/license required | Select the original download account. Another account may not obtain the app. |
| Session expired/Keychain unavailable | Sign in again; review the system access prompt and unlock the login keychain if needed. |
| Rejected verification code | Check the current code and retry in the form. Never include it in reports. |
| Apple request failed/unavailable download | Check connection, account, app availability, and any offered alternative version. |
| Missing/invalid IPA | Reimport a valid original or retry an authorized download. |
| Library archive busy | Finish/cancel tasks using it before retrying deletion. |
| Installation failed/timed out/interrupted | Reconnect/unlock, refresh, and inspect actual phone state before retrying. Preserve the existing app. |
| Installed app requests Apple Account | The IPA may need its original account, separate from the service's login. |

For reports, include app/macOS/iOS versions, the attempted action, and the displayed error. Review screenshots/activity for personal information first.

## Validation and limits

Verified on macOS 15.6.1/Apple Silicon with iPhone 16 Pro Max/iOS 18.5: direct metadata/discovery, fresh GUI sign-in, real Craftersy 5.1 download/validation, reuse, persistence, synthetic import/Trash deletion, and native settings/selection/queue resizing. Packaging checks cover signatures, dependencies, DMG integrity, and relocation on the same Mac.

For 0.1.4, **22 portable Core tests / 115 assertions**, Go helper race tests and vet, and the C bridge AddressSanitizer/UndefinedBehaviorSanitizer checks passed. The native build and bundle signature/dependency checks also passed. DMG and GUI results are recorded separately in the current QA/status documents; the version rename does not establish new live-device or clean-Mac coverage.

Pending: complete install/readback/launch on iPhone 17/a second device; live second-account and invalid-code/session-expiry recovery; iOS 27; clean-user/clean-Mac auth/runtime setup; downloaded DMG/Gatekeeper; full accessibility and multi-device drag checks. Three/five-phone layout fixtures are synthetic. Earlier standalone CLI success does not verify this app's bridge.

See [QA evidence](docs/QA.md), [acceptance](docs/ACCEPTANCE.md), and [status](STATUS.md) for scope and dates.

## Build and contribute

Developers need an Apple Silicon Mac, macOS 15+, Swift/Clang CLT or Xcode, Go 1.26+, Python 3, and pinned native inputs from [vendor/manifest.json](vendor/manifest.json). The dependency script verifies installed versions; it does not provision/upgrade them automatically.

```sh
./scripts/bootstrap-deps.sh
./scripts/test-core.sh
./scripts/test-device-bridge.sh
./scripts/build-app.sh
./scripts/package-dmg.sh
./scripts/verify-bundle.sh 'dist/iPhone App Transfer.app'
```

[Build instructions](scripts/README.md) cover dependencies, the local CLT wrapper, configuration, and output verification. The portable runner shares Core test bodies; full Xcode also supports `./scripts/swiftpm.sh test`.

Build defaults are **0.1.5 (6)** for the account-clarification update. The local build has been approved for source delivery. Build/package commands do not publish a GitHub prerelease; the public DMG remains v0.1.4 until a new release is published.

Read-only diagnostics: `'dist/iPhone App Transfer.app/Contents/MacOS/AppTransfer' --diagnostics`. `test-device-bridge.sh --live-read-only` adds device reads without install/removal. Explicit `--demo` uses synthetic data and disables live actions; normal failure never becomes demo success.

Architecture: SwiftUI/AppKit, direct [libimobiledevice C bridge](Sources/DeviceBridge/README.md), bundled [Go helper](Helpers/AppStoreBridge/README.md) using pinned ipatool 2.7.0 core. No WebView, shell-output IPC, or server.

Contributors/agents should read [AGENTS.md](AGENTS.md), current [STATUS.md](STATUS.md), [product](PRODUCT.md), [design](DESIGN.md), [architecture](docs/ARCHITECTURE.md), [research](research/FINDINGS.md), and [implementation plan](IMPLEMENTATION_PLAN.md). [START_HERE.md](START_HERE.md) starts with the current continuation scope and preserves the original handoff as history; the MVP already exists. [GitHub CLI and publication](docs/GITHUB_SETUP.md) documents repository access, delivery history, and public preview verification. Prototype HTML is only a design reference.

## Licenses

Dependencies retain their licenses: see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), the pinned manifest, and preserved ipatool MIT license/patch notes. Packaged builds include dependency notices/full license texts. Apple runtime images retain Apple's terms and are not redistributed inside the app.

**The license for this project's original code has not yet been chosen.** Public source visibility does not supply an open-source license; dependency licenses do not separately license that code. Repository/binary publication and completion of preview validation are distinct steps.
