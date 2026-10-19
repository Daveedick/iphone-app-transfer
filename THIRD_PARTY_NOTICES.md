# Third-party notices

iPhone App Transfer dynamically links the following libraries. Exact source versions,
archive SHA-256 values and the developer binary fingerprints are recorded in
`vendor/manifest.json`. Full license texts are copied into the application at
`Contents/Resources/Licenses`; source URLs accompany every native component.

| Component | Version used | License | Source |
| --- | --- | --- | --- |
| libimobiledevice library | 1.4.0 (Homebrew revision 1) | LGPL-2.1-or-later | https://github.com/libimobiledevice/libimobiledevice |
| libplist C library | 2.8.0 | LGPL-2.1-or-later | https://github.com/libimobiledevice/libplist |
| libusbmuxd library | 2.1.1 (Homebrew revision 1) | LGPL-2.1-or-later | https://github.com/libimobiledevice/libusbmuxd |
| libimobiledevice-glue | 1.3.3 | LGPL-2.1-or-later | https://github.com/libimobiledevice/libimobiledevice-glue |
| OpenSSL libssl/libcrypto | 3.6.5 | Apache-2.0 | https://github.com/openssl/openssl |
| ipatool core | 2.7.0, commit 4484b55d366e177ae6c89758c61588712c572fad | MIT | https://github.com/majd/ipatool |

The libraries remain separate replaceable dylibs inside `Contents/Frameworks`.
This app does not copy/link the GPL ideviceinstaller CLI or ship its executable.
The parent libimobiledevice projects also contain differently licensed tools;
the table describes the dynamically linked libraries, not every file upstream.
Changes to native binary install names are made solely for bundle relocation.
The Swift/C bridge and build scripts are available with the app source. Users may
replace compatible LGPL libraries for their own use and reapply ad-hoc integrity
signatures. There is no Developer ID signature or notarization to imply otherwise.

The Go helper includes ipatool and its transitive Go modules. Their resolved
versions are in `Helpers/AppStoreBridge/go.mod`/`go.sum`; the bundle's
`Licenses/go-modules.json` records collected notices and full license filenames.
The vendored upstream MIT license and the documented cache-namespace-only patch
are preserved under `Helpers/AppStoreBridge/upstream/ipatool` and `UPSTREAM.md`.

The app uses Apple's system frameworks, Swift runtime and system libarchive.
The libarchive development headers are a build prerequisite; its Homebrew dylib
is not distributed. Apple's frameworks and runtime remain OS components.

The first authorized App Store login or download may cause ipatool to fetch pinned Unicorn
2.1.4 runtime artifacts and Apple SAP images into its dedicated user cache.
Apple SAP images come from Apple's software-distribution servers; Unicorn runtime artifacts come from PyPI. Those are not embedded in the DMG. Unicorn is a separate upstream project
(https://github.com/unicorn-engine/unicorn) with its own LGPL-2.1 licensing;
Apple-provided images retain Apple's terms. Download source/hashes are in the
pinned ipatool source. iPhone App Transfer does not redistribute Apple binaries as its
own assets. Network access and clean-user runtime preparation require separate
acceptance checks.

The 0.1.4 delivery is a private preview; its live second-device/second-account and clean-Mac checks remain pending. Before public binary distribution,
preserve the supplied source/notice package and review the resolved Go module
notice report and source-distribution obligations for the exact shipped build.
No license for the project's original code is chosen by this notice document.
