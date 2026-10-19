/* Standalone focused safety tests. The bridge is included to exercise internal
 * archive preparation/status handling without making any device connection. */
#include "../../Sources/DeviceBridge/device_bridge.c"
#include <assert.h>

static const char info_xml[]="<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>test.synthetic.app</string><key>CFBundleExecutable</key><string>Runner</string></dict></plist>";
static const char metadata_xml[]="<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>itemId</key><integer>123</integer></dict></plist>";

static void entry_data(struct archive *archive,const char *name,const char *data,size_t size) {
    struct archive_entry *entry=archive_entry_new();
    archive_entry_set_pathname(entry,name);
    archive_entry_set_size(entry,size);
    archive_entry_set_filetype(entry,AE_IFREG);
    archive_entry_set_perm(entry,0600);
    assert(archive_write_header(archive,entry)==ARCHIVE_OK);
    assert(archive_write_data(archive,data,size)==(la_ssize_t)size);
    archive_entry_free(entry);
}
static int fixture(int duplicate) {
    char path[]="/tmp/app-transfer-bridge-test-XXXXXX";
    int fd=mkstemp(path); assert(fd>=0); unlink(path);
    struct archive *archive=archive_write_new();
    assert(archive_write_set_format_zip(archive)==ARCHIVE_OK);
    assert(archive_write_open_fd(archive,fd)==ARCHIVE_OK);
    entry_data(archive,"Payload/Display.app/Info.plist",info_xml,strlen(info_xml));
    entry_data(archive,"Payload/Display.app/Frameworks/Nested.app/Info.plist",info_xml,strlen(info_xml));
    entry_data(archive,"Payload/Display.app/SC_Info/Runner.sinf","SYNTHETIC-SINF",14);
    entry_data(archive,"Payload/Display.app/PlugIns/Widget.appex/SC_Info/Runner.sinf","WRONG",5);
    entry_data(archive,"iTunesMetadata.plist",metadata_xml,strlen(metadata_xml));
    if(duplicate)entry_data(archive,"Payload/Other.app/Info.plist",info_xml,strlen(info_xml));
    assert(archive_write_close(archive)==ARCHIVE_OK);
    archive_write_free(archive);
    return fd;
}
static void archive_options(void) {
    char *error=NULL; plist_t options=NULL;
    int fd=fixture(0);
    assert(install_options_from_archive(fd,&options,&error)==AT_DEVICE_OK);
    assert(!error);
    char *bundle=NULL;plist_get_string_val(plist_dict_get_item(options,"CFBundleIdentifier"),&bundle);
    assert(bundle&&strcmp(bundle,"test.synthetic.app")==0);free(bundle);
    char *sinf=NULL;uint64_t size=0;
    plist_get_data_val(plist_dict_get_item(options,"ApplicationSINF"),&sinf,&size);
    assert(size==14&&memcmp(sinf,"SYNTHETIC-SINF",14)==0);free(sinf);
    assert(plist_get_node_type(plist_dict_get_item(options,"iTunesMetadata"))==PLIST_DATA);
    assert(lseek(fd,0,SEEK_CUR)==0);
    instproxy_client_options_free(options);close(fd);
    options=NULL;fd=fixture(1);
    assert(install_options_from_archive(fd,&options,&error)==AT_DEVICE_IO_ERROR);
    assert(!options&&error);free(error);error=NULL;close(fd);
    char path[]="/tmp/app-transfer-bridge-bad-XXXXXX";fd=mkstemp(path);assert(fd>=0);unlink(path);
    assert(write(fd,"not-a-zip",9)==9);
    assert(install_options_from_archive(fd,&options,&error)==AT_DEVICE_IO_ERROR);
    assert(!options&&error);free(error);close(fd);
    assert(primary_info_path("Payload/A.app/Info.plist"));
    assert(!primary_info_path("Payload/A.app/Frameworks/B.app/Info.plist"));
    assert(!primary_info_path("Payload/A.app/PlugIns/B.appex/Info.plist"));
    puts("archive options: correct primary app/SINF/metadata; duplicate and invalid ZIP rejected");
}
static void terminal_status(void) {
    InstallState state={0};pthread_mutex_init(&state.mutex,NULL);pthread_cond_init(&state.changed,NULL);
    plist_t status=plist_new_dict();
    plist_dict_set_item(status,"Status",plist_new_string("Installing"));
    plist_dict_set_item(status,"PercentComplete",plist_new_uint(100));
    installation_status(NULL,status,&state);
    assert(!state.finished&&!state.success);
    plist_dict_set_item(status,"Status",plist_new_string("Complete"));
    installation_status(NULL,status,&state);
    assert(state.finished&&state.success);
    state.finished=0;state.success=0;
    plist_dict_set_item(status,"Error",plist_new_string("ApplicationVerificationFailed"));
    installation_status(NULL,status,&state);
    assert(state.finished&&!state.success);
    assert(strcmp(state.error_name,"ApplicationVerificationFailed")==0);
    plist_free(status);pthread_cond_destroy(&state.changed);pthread_mutex_destroy(&state.mutex);
    puts("terminal status: 100 percent alone is not success; Complete required; error wins");
}
static void invalid_arguments(void) {
    char *xml=(char *)1,*error=NULL;
    assert(at_device_readback_app("unused",NULL,&xml,&error)==AT_DEVICE_INVALID_ARGUMENT);
    assert(!xml&&error);free(error);error=NULL;
    assert(at_device_install_ipa("unused","relative.ipa",NULL,NULL,&error)==AT_DEVICE_INVALID_ARGUMENT);
    assert(error);free(error);error=NULL;
    assert(at_device_get_info(NULL,&xml,&error)==AT_DEVICE_INVALID_ARGUMENT);
    assert(!xml&&error);free(error);error=NULL;
    at_device_events_stop(NULL);at_device_free(NULL);
    puts("invalid arguments: no device requests, outputs reset, null cleanup safe");
}
int main(void) { archive_options();terminal_status();invalid_arguments();puts("DeviceBridge safety checks passed; no phone connected or mutated by tests.");return 0; }
