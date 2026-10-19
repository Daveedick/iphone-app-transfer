# DeviceBridge

The stable public boundary is `include/DeviceBridge.h`. Functions block and must
run on a dedicated background queue. Inputs stay alive for a call; copy callback
strings before returning. Every returned XML/error/PNG buffer is caller-owned and
must be released by `at_device_free`, including errors on failure. Output XML is
NUL terminated. Parsing can use Foundation `PropertyListSerialization`.

`lookup_apps` and `readback_app` return a dictionary keyed by bundle ID. The
`iTunesMetadata` field is plist DATA that itself contains an XML/binary plist. It
may contain an Apple Account email and must not be dumped in diagnostics.

`get_info` deliberately selects public properties rather than returning the full
lockdown dictionary. `PasswordProtected` indicates a configured passcode, **not**
that the phone is presently locked. Determine a locked/untrusted UI state from the
typed result. Optional free space may be absent. Device identities are always
specific USB UDIDs; neither Wi-Fi nor the first available device is substituted.

The handshake can cause the system Trust prompt. No pair reset, unpair, settings,
backup or app-data access is performed. Events support multiple independent
subscriptions. Stop waits for callbacks to finish; never stop from a callback.

The installation path validates the local file shape, reads bounded Info/SINF/
iTunesMetadata in memory through macOS libarchive, stages only a random unique
file through AFC, then observes `installation_proxy` terminal status. Request
acceptance is not success. The caller must read back the exact target bundle,
version/build and offloaded state, and treat launch/Apple Account activation as
separate checks. The original/staged app is never automatically uninstalled.
Only the bridge's exact staged path is removed during cleanup, never a directory.

Cancellation is honored while uploading; installation is allowed to settle.
Disconnect yields a typed unavailable result and requires readback on reconnect.
An absent terminal result times out after 15 minutes; a transport library receive
may add its own short timeout while joining the callback thread. A timeout does
not prove the device rolled the installation back. The optional uninstall API is
destructive, never used as repair, and requires a separately confirmed UI flow.

## Development dependencies

Header search: `/opt/homebrew/include`,
`/opt/homebrew/opt/libarchive/include` (archive headers only; CLT omits them).
Dynamic links: `imobiledevice-1.0`, `plist-2.0`, **system** `archive`.
On this Mac `-larchive` resolves `/usr/lib/libarchive.2.dylib`; it requires no
bundled third-party archive runtime. Package/bundle the other dependencies with
relative install names; Homebrew is a development prerequisite only.

## Bounded verification

Compile a read-only smoke helper:

```sh
clang -std=c11 -Wall -Wextra -Werror \
  -I Sources/DeviceBridge/include -I /opt/homebrew/include \
  -I /opt/homebrew/opt/libarchive/include \
  Sources/DeviceBridge/device_bridge.c Helpers/DeviceProbe/main.c \
  -L /opt/homebrew/lib -Wl,-rpath,/opt/homebrew/lib \
  -limobiledevice-1.0 -lplist-2.0 -larchive -o /tmp/app-transfer-device-probe
/tmp/app-transfer-device-probe
```

The probe reports counts/model/iOS and optional targeted icon/readback status.
It never installs, removes, lists account identities, or writes inventory. On
19 October 2026 live USB iOS 18.5 reading returned 333 apps, 333 metadata fields
and 27 offloaded records. iOS 27, actual unplug/replug event delivery and a live
installation remain independent checks; successful subscription is not a hotplug
test. No live uninstall has been performed.

Primary API references: [libimobiledevice 1.4.0 installation proxy](https://github.com/libimobiledevice/libimobiledevice/blob/1.4.0/include/libimobiledevice/installation_proxy.h),
[lockdown](https://github.com/libimobiledevice/libimobiledevice/blob/1.4.0/include/libimobiledevice/lockdown.h),
[AFC](https://github.com/libimobiledevice/libimobiledevice/blob/1.4.0/include/libimobiledevice/afc.h).
The implementation uses public library interfaces; it does not copy GPL CLI code.
