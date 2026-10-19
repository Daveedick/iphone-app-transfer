#include "ArchiveBridge.h"
#include <archive.h>
#include <archive_entry.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>

static const uint64_t max_total = 12ULL * 1024 * 1024 * 1024;
static const size_t max_capture = 16 * 1024 * 1024;
static int fail(char **error, const char *message) { if (error) *error = strdup(message); return -1; }
static int safe_path(const char *p) {
    if (!p || !*p || p[0]=='/' || strchr(p,'\\') || strchr(p,':')) return 0;
    const char *part = p;
    while (*part) { const char *end=strchr(part,'/'); size_t n=end?(size_t)(end-part):strlen(part); if ((n==2 && part[0]=='.' && part[1]=='.') || (n==1 && part[0]=='.')) return 0; if (!end) break; part=end+1; }
    return 1;
}
static int main_info(const char *p) {
    if (strncmp(p,"Payload/",8)) return 0;
    const char *end=strchr(p+8,'/');
    return end && end-p>=4 && !strncmp(end-4,".app",4) && !strcmp(end,"/Info.plist");
}
void at_archive_free(void *p) { free(p); }
void at_archive_info_free(ATArchiveInfo *r) { if (!r) return; free(r->info); free(r->metadata); free(r->app_path); memset(r,0,sizeof(*r)); }
int at_archive_inspect(const char *path, ATArchiveInfo *out, char **error) {
    if (error) *error=NULL; if (!out) return fail(error,"Missing archive output"); memset(out,0,sizeof(*out));
    struct archive *a=archive_read_new(); if (!a) return fail(error,"Could not create ZIP reader");
    archive_read_support_format_zip(a); archive_read_support_filter_none(a);
    int result=-1, count=0, found=0, status; uint64_t total=0; struct archive_entry *entry;
    if (archive_read_open_filename(a,path,128*1024)!=ARCHIVE_OK) { fail(error,"Cannot open IPA archive"); goto done; }
    while ((status=archive_read_next_header(a,&entry))==ARCHIVE_OK) {
        const char *name=archive_entry_pathname(entry);
        if (++count>200000 || !safe_path(name) || archive_entry_symlink(entry) || archive_entry_hardlink(entry)) { fail(error,"Archive contains unsafe paths, links, or too many entries"); goto done; }
        const int info=main_info(name), metadata=!strcmp(name,"iTunesMetadata.plist");
        if (info && ++found>1) { fail(error,"IPA contains more than one main application"); goto done; }
        if (strstr(name,"/SC_Info/") && strlen(name)>5 && !strcmp(name+strlen(name)-5,".sinf")) out->has_sinf=1;
        void **capture=info?&out->info:metadata?&out->metadata:NULL;
        size_t *capture_length=info?&out->info_length:metadata?&out->metadata_length:NULL;
        if (capture && *capture) { fail(error,"Duplicate archive metadata"); goto done; }
        unsigned char buffer[128*1024]; la_ssize_t n;
        while ((n=archive_read_data(a,buffer,sizeof(buffer)))>0) {
            total+=(uint64_t)n;
            if (total>max_total) { fail(error,"Uncompressed archive is too large"); goto done; }
            if (capture) {
                if (*capture_length+(size_t)n>max_capture) { fail(error,"Archive metadata is too large"); goto done; }
                void *next=realloc(*capture,*capture_length+(size_t)n); if (!next) { fail(error,"Not enough memory"); goto done; }
                *capture=next; memcpy((char*)*capture+*capture_length,buffer,(size_t)n); *capture_length+=(size_t)n;
            }
        }
        if (n<0) { fail(error,"IPA is damaged or its ZIP checksum is invalid"); goto done; }
        if (info) { const char *slash=strchr(name+8,'/'); out->app_path=strndup(name,(size_t)(slash-name)); }
    }
    if (status!=ARCHIVE_EOF || found!=1 || !out->info_length) { fail(error,"Invalid IPA: one Payload application is required"); goto done; }
    result=0;
done:
    archive_read_free(a); if (result) at_archive_info_free(out); return result;
}
int at_archive_read_entry(const char *path,const char *name,void **data,size_t *length,char **error) {
    if (error) *error=NULL; *data=NULL; *length=0;
    if (!safe_path(name)) return fail(error,"Unsafe archive entry");
    struct archive *a=archive_read_new(); archive_read_support_format_zip(a); archive_read_support_filter_none(a);
    int result=-1; struct archive_entry *entry;
    if (archive_read_open_filename(a,path,128*1024)!=ARCHIVE_OK) { fail(error,"Cannot open IPA archive"); goto done; }
    while (archive_read_next_header(a,&entry)==ARCHIVE_OK) {
        if (strcmp(archive_entry_pathname(entry),name)) { archive_read_data_skip(a); continue; }
        if (archive_entry_symlink(entry)||archive_entry_hardlink(entry)) { fail(error,"Unsafe linked archive entry"); goto done; }
        unsigned char buffer[65536]; la_ssize_t n;
        while ((n=archive_read_data(a,buffer,sizeof(buffer)))>0) {
            if (*length+(size_t)n>max_capture) { fail(error,"Archive entry is too large"); goto done; }
            void *next=realloc(*data,*length+(size_t)n); if (!next) { fail(error,"Not enough memory"); goto done; }
            *data=next; memcpy((char*)*data+*length,buffer,(size_t)n); *length+=(size_t)n;
        }
        if(n<0) { fail(error,"Damaged archive entry"); goto done; } result=0; goto done;
    }
    fail(error,"Archive entry not found");
done: archive_read_free(a); if(result) {free(*data);*data=NULL;*length=0;} return result;
}
