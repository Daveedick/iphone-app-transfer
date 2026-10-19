#ifndef APP_TRANSFER_DEVICE_BRIDGE_H
#define APP_TRANSFER_DEVICE_BRIDGE_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Blocking calls: run off the UI thread. Output buffers are caller-owned;
 * release with at_device_free(). Errors never include account metadata. */
typedef enum {
 AT_DEVICE_OK=0, AT_DEVICE_INVALID_ARGUMENT=1, AT_DEVICE_UNAVAILABLE=2,
 AT_DEVICE_LOCKED=3, AT_DEVICE_TRUST_PENDING=4, AT_DEVICE_TRUST_DENIED=5,
 AT_DEVICE_SERVICE_ERROR=6, AT_DEVICE_IO_ERROR=7, AT_DEVICE_INSTALL_FAILED=8,
 AT_DEVICE_NOT_FOUND=9, AT_DEVICE_CANCELED=10, AT_DEVICE_TIMEOUT=11,
 AT_DEVICE_OUT_OF_MEMORY=12
} ATDeviceResult;
void at_device_free(void *buffer);
/* XML plist array: {UDID:string, ConnectionType:"USB"}. */
ATDeviceResult at_device_list_usb(char **out_xml,char **out_error);
/* Selected public lockdown keys and optional TotalDataCapacity/Available.
 * Handshake may show Trust; pair records are never reset or deleted. */
ATDeviceResult at_device_get_info(const char *udid,char **out_xml,char **out_error);
/* XML plist dict keyed by bundle ID; ShowPlaceholders=true, iTunesMetadata DATA.
 * Parse private metadata in memory; never log/persist raw result as diagnostics. */
ATDeviceResult at_device_lookup_apps(const char *udid,char **out_xml,char **out_error);
ATDeviceResult at_device_readback_app(const char *udid,const char *bundle_id,char **out_xml,char **out_error);
ATDeviceResult at_device_get_icon(const char *udid,const char *bundle_id,uint8_t **out_png,size_t *out_size,char **out_error);
/* Worker callback: event 1 added, 2 removed, 3 paired. Copy UDID before return.
 * Keep context alive through stop; never stop from within callback. */
typedef struct ATDeviceListener ATDeviceListener;
typedef void (*ATDeviceEventCallback)(int event,const char *udid,void *context);
ATDeviceResult at_device_events_start(ATDeviceEventCallback callback,void *context,ATDeviceListener **out_listener,char **out_error);
void at_device_events_stop(ATDeviceListener *listener);
/* Return nonzero to cancel uploading. Installing waits for terminal status.
 * percent=-1 means unknown; strings live only for callback duration.
 * Never synchronously wait on MainActor from callback. Success requires explicit
 * Complete; caller MUST read back bundle/build/version on same target afterwards.
 * Success does not prove launch or entitlement. */
typedef int (*ATDeviceProgressCallback)(const char *stage,int percent,const char *message,void *context);
ATDeviceResult at_device_install_ipa(const char *udid,const char *local_ipa_path,ATDeviceProgressCallback callback,void *context,char **out_error);
/* OPTIONAL destructive API: explicit UI device/app/data-loss confirmation.
 * Never automatic install repair. Caller must verify disappearance afterward. */
ATDeviceResult at_device_uninstall_app(const char *udid,const char *bundle_id,ATDeviceProgressCallback callback,void *context,char **out_error);
#ifdef __cplusplus
}
#endif
#endif
