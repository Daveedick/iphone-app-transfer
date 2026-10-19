#ifndef AT_ARCHIVE_BRIDGE_H
#define AT_ARCHIVE_BRIDGE_H
#include <stddef.h>
typedef struct {
    void *info; size_t info_length;
    void *metadata; size_t metadata_length;
    int has_sinf;
    char *app_path;
} ATArchiveInfo;
/* Streams every entry (including CRC validation); never extracts paths to disk. */
int at_archive_inspect(const char *path, ATArchiveInfo *result, char **error);
int at_archive_read_entry(const char *path, const char *entry, void **data, size_t *length, char **error);
void at_archive_info_free(ATArchiveInfo *result);
void at_archive_free(void *memory);
#endif
