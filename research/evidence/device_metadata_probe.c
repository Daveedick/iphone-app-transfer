#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/installation_proxy.h>
#include <plist/plist.h>

/* Read-only experiment: no iMazing files, no application install APIs. */
int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s UDID OUTPUT_PLIST SHOW_PLACEHOLDERS\n", argv[0]);
        return 2;
    }
    idevice_t device = NULL;
    instproxy_client_t client = NULL;
    plist_t options = NULL, result = NULL;
    char *xml = NULL;
    uint32_t length = 0;
    int status = 1, fd = -1;
    int error = idevice_new_with_options(&device, argv[1], IDEVICE_LOOKUP_USBMUX);
    if (error != IDEVICE_E_SUCCESS) { fprintf(stderr, "device error: %d\n", error); goto done; }
    error = instproxy_client_start_service(device, &client, "AppTransferMetadataProbe");
    if (error != INSTPROXY_E_SUCCESS) { fprintf(stderr, "service error: %d\n", error); goto done; }
    options = instproxy_client_options_new();
    plist_dict_set_item(options, "ApplicationType", plist_new_string("User"));
    plist_dict_set_item(options, "ShowPlaceholders", plist_new_bool(atoi(argv[3]) != 0));
    instproxy_client_options_set_return_attributes(options,
        "CFBundleIdentifier", "CFBundleDisplayName", "CFBundleShortVersionString",
        "CFBundleVersion", "IsDemotedApp", "ApplicationType", "iTunesMetadata", NULL);
    error = instproxy_lookup(client, NULL, options, &result);
    if (error != INSTPROXY_E_SUCCESS || !result) { fprintf(stderr, "lookup error: %d\n", error); goto done; }
    if (plist_to_xml(result, &xml, &length) != PLIST_ERR_SUCCESS) goto done;
    fd = open(argv[2], O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd < 0) { perror("output"); goto done; }
    size_t written = 0;
    while (written < length) {
        ssize_t n = write(fd, xml + written, length - written);
        if (n <= 0) { perror("write"); goto done; }
        written += (size_t)n;
    }
    printf("Read-only library lookup succeeded; records=%u; placeholders=%s\n",
           plist_dict_get_size(result), argv[3]);
    status = 0;
done:
    if (fd >= 0) close(fd);
    if (xml) plist_mem_free(xml);
    if (result) plist_free(result);
    if (options) instproxy_client_options_free(options);
    if (client) instproxy_client_free(client);
    if (device) idevice_free(device);
    return status;
}
