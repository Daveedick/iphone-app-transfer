# AppStoreBridge

Bundled macOS JSON-Lines helper using the pinned **ipatool 2.7.0 core**, not CLI output parsing. No shell, daemon, terminal prompt, or inherited ipatool account state. Run one child process, keep stdin open, use pipes for credentials, and kill/respawn after an unrecoverable pipe/process failure. Production stdout is protocol-only. Errors are deliberately allowlisted and never contain raw upstream text, signed URLs, tokens, passwords, OTPs, or Apple response bodies.

## Build

Prerequisites for developers: Go 1.26+, macOS CLT. End users need neither.

```sh
cd Helpers/AppStoreBridge
CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 MACOSX_DEPLOYMENT_TARGET=15.0 go build -trimpath -o ../../.build/helpers/AppStoreBridge ./cmd/appstorebridge
go test -race ./internal/bridge
```

For sandboxed build environments, point `GOCACHE`, `GOMODCACHE`, `GOPATH` and `CLANG_MODULE_CACHE_PATH` at writable build-cache folders. `go.mod`/`go.sum` pin transitive versions; `replace` points at the recorded official source under `upstream/ipatool`. See `UPSTREAM.md`. Bundle the executable at `Contents/Helpers/AppStoreBridge`. No Go runtime is required. Nested runtime libraries downloaded on first login or download have their own upstream checksums; the packaging/runtime verification must include this first-run path.

## Framing and events

Request (one object per line, max 1 MiB; `requestId` is unique within the process):

```json
{"protocolVersion":1,"requestId":"uuid","command":"hello","payload":{}}
```

Event:

```json
{"protocolVersion":1,"requestId":"uuid","operationId":"uuid","event":"completed","payload":{},"error":{"code":"license.required","message":"Safe readable text","retryable":true}}
```

`operationId` is the requestId. Error is present on failed events only. `ready`, `completed`, `failed`, `canceled`, `auth.succeeded` are terminal for that request. `auth.preparing`, `auth.codeRequired`, `download.progress` are intermediate. Every request receives its own response: `auth.submitCode` and cancellation commands return an acknowledgement independently of the original request's eventual result. Account and application identifiers are strings except numeric `storeItemId` (JSON integer/int64).

### Commands

| Command | Payload | Result/event payload |
| --- | --- | --- |
| `hello` | `{}` | `ready`: `{helperVersion,upstreamVersion,protocolVersion,capabilities:[string]}` |
| `account.list` | `{}` | `completed`: `{accounts:[{id,email,name,storefront,authenticated}]}` |
| `auth.begin` | `{accountId?:UUID,email,password}` | `auth.preparing`: `{accountId,message}`; then `auth.codeRequired`: `{accountId,invalidPreviousCode}` or `auth.succeeded`: `{account:{id,email,name,storefront,authenticated}}` |
| `auth.submitCode` | `{accountId,code:"123456"}` | `completed`: `{accepted:true}`; original auth request resumes |
| `auth.cancel` | `{accountId}` | `completed`: `{cancelRequested:bool}` |
| `account.remove` | `{accountId}` | `completed`: `{removed:true,accountId}` |
| `app.versionInfo` | `{accountId,storeItemId,bundleId,externalVersionId}` | `completed`: `{accountId,storeItemId,bundleId,externalVersionId,version,releaseDate}` |
| `app.versions` | `{accountId,storeItemId,bundleId}` | `completed`: `{externalVersionIds:[string],latestExternalVersionId:string}` |
| `app.download` | `{accountId,storeItemId,bundleId,externalVersionId,outputPath}` | `download.progress`: `{bytesReceived,totalBytes?,fraction?}`; `completed`: `{destinationPath,accountId,storeItemId,bundleId,externalVersionId,bytes}` |
| `operation.cancel` | `{operationId}` | `completed`: `{cancelRequested:bool}` |

`auth.begin` may omit accountId to create a UUID or reuse an existing matching email. Reauthentication should pass the existing accountId. Password lives in memory only while logging in/awaiting verification; never put it in command args/env. The helper strips upstream's password field before storing the session. Enter the six-digit OTP with `auth.submitCode`; invalid format is rejected without echoing it. A 10-minute wait and five code attempts bound the pending login. Closing a popover should not send cancellation unless the user explicitly cancels authentication.

`app.versionInfo` with an empty externalVersionId queries the current Apple offer; an actual download requires an explicit nonempty ID. Resolve alternatives through `app.versions`, show a version choice in the GUI, then download that chosen ID. The helper **never buys a license, switches accounts, silently changes version, or extracts an installed app from a phone**.

`outputPath` must be a new absolute canonical path with an existing real parent directory (no symlink ancestors). Both it and the upstream `.tmp` path must not exist. The parent owns a protected managed staging directory and supplies a random job-specific `.partial` path. The helper restricts new files to 0600 after completion; the parent must set staging directory mode 0700. A successful download is **not archive validation or phone installation**: the Swift library service must verify CRC, bundle/version/build, SINF provenance and SHA-256 before publishing the library item. Failed/canceled outputs remain staging-only; parent handles safe cleanup/recovery.

## Isolation and cancellation

macOS Keychain generic-password service `com.apptransfer.AppStoreBridge.v1` contains account registry and separate `account/<UUID>/...` items. Cookies, session tokens and upstream kbsync credentials are stored only in Keychain, never a JSON cookie file. Each operation gets its own in-memory jar loaded solely from that account's Keychain namespace. No `~/.ipatool` or iMazing read. Removing an account deletes its local auth entries, leaving library IPA ownership references intact.

One active operation per account is enforced; other accounts may operate independently. The Swift coordinator still executes its transfer queue sequentially. Download and version/list requests use cancellation contexts where upstream supports them. Upstream Login has no context, so cancellation discards the result at a safe boundary; it does **not** claim to abort every network/SAP instruction immediately. Login writes are transactionally staged in memory until success; a canceled login does not commit them. The process may be terminated after pipe close without generating fake success.

First login or download may download pinned Apple SAP components and Unicorn runtime; auth.preparing is indeterminate progress (do not invent a percentage). No live account login/download was performed by helper tests. New-account GUI login, OTP, actual download, second account isolation, and clean-user/runtime/Gatekeeper behavior must be verified during integration.

## Verification performed

- `go test -race ./internal/bridge`: 11 focused synthetic tests pass (native Keychain test skipped by default).
- `go vet ./internal/bridge ./cmd/appstorebridge`: pass.
- Built arm64 executable: `hello`→ready; fresh app-owned `account.list`→empty accounts outside the development sandbox.
- Opt-in `APP_TRANSFER_RUN_KEYCHAIN_TEST=1 go test -run TestSystemKeychainRoundTrip -count=1 ./internal/bridge` outside sandbox: native Keychain create/read/update/delete passed with public synthetic bytes in a unique `self-test/UUID` entry; entry removed afterward. No real account session was read/written.
- Sandboxed Security.framework may return OSStatus -67674; this is surfaced as `keychain.unavailable`, never treated as an empty account list or successful auth.
- Integration 19 October 2026: the user completed a fresh GUI sign-in; this helper downloaded real Craftersy 5.1 into the managed library, and the account survived relaunch. See ../../docs/QA.md. No password/OTP contents were inspected.
- Still unverified: separately observed real invalid-OTP recovery, second-account live behavior and first-run authentication assets in a clean macOS profile.
