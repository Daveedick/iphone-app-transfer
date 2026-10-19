# Pinned upstream

- Repository: https://github.com/majd/ipatool
- Tag: `v2.7.0`
- Commit: `4484b55d366e177ae6c89758c61588712c572fad`
- Go module checksum: `h1:vUnVsSfH4TQNCgxouApwcQgiliwtNCwv7/OK6QfFaSE=`
- Go module go.mod checksum: `h1:B/K6VaXK/u69YzkUi7AeUlNlMfuq3d2/7UQwE4WetFc=`
- License: MIT, preserved in `upstream/ipatool/LICENSE`.

`upstream/ipatool` is the official Go module archive for this tag, not the unversioned downloaded source directory. Local patch: replace the runtime-cache namespace `ipatool` with `App Transfer` in exactly `internal/sap/assets/assets.go`, `internal/sap/assets/storeagent.go`, `internal/sap/unicorn/cache_runtime.go`. This isolates Apple SAP image/Unicorn caches from a standalone ipatool installation. No protocol or signing changes.

The Go helper embeds upstream code, not Apple binaries. First authorized login or download may download pinned Apple SAP images from Apple's `swcdn.apple.com` update payload and a pinned Unicorn 2.1.4 runtime from `files.pythonhosted.org`. Upstream validates hashes and lengths before use. Cache is `~/Library/Caches/App Transfer/{sap,unicorn}`. Runtime/license details remain in upstream sources; `go list -m all` describes linked Go dependencies. Clean first-login and clean-user tests remain required. End users do not need Go or Homebrew.

The product is now named **iPhone App Transfer**. The `App Transfer` cache directory is intentionally retained for compatibility, alongside the unchanged Keychain service and local library paths. This display-name change does not migrate or discard existing runtime assets.
