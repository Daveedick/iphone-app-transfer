#include "DeviceBridge.h"
#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/lockdown.h>
#include <libimobiledevice/installation_proxy.h>
#include <libimobiledevice/afc.h>
#include <libimobiledevice/sbservices.h>
#include <plist/plist.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <archive.h>
#include <archive_entry.h>

#define AT_LABEL "AppTransfer"
#define AT_UPLOAD_CHUNK (1024 * 1024)
#define AT_OPERATION_TIMEOUT_SECONDS (15 * 60)
#define AT_MAX_INSTALL_METADATA (8 * 1024 * 1024)

void at_device_free(void *buffer) { free(buffer); }

static ATDeviceResult fail(ATDeviceResult code, char **error, const char *message) {
    if (error) *error = strdup(message);
    return code;
}
static int valid_string(const char *value) { return value && value[0]; }
static ATDeviceResult lockdown_failure(lockdownd_error_t code, char **error) {
    switch (code) {
        case LOCKDOWN_E_PASSWORD_PROTECTED:
        case LOCKDOWN_E_ESCROW_LOCKED:
            return fail(AT_DEVICE_LOCKED,error,"Unlock the iPhone and keep it on the Home Screen.");
        case LOCKDOWN_E_PAIRING_DIALOG_RESPONSE_PENDING:
        case LOCKDOWN_E_MISSING_PAIR_RECORD:
        case LOCKDOWN_E_INVALID_PAIR_RECORD:
        case LOCKDOWN_E_MISSING_HOST_ID:
        case LOCKDOWN_E_INVALID_HOST_ID:
        case LOCKDOWN_E_PAIRING_FAILED:
            return fail(AT_DEVICE_TRUST_PENDING,error,"Confirm Trust on the iPhone, then reconnect if needed.");
        case LOCKDOWN_E_USER_DENIED_PAIRING:
        case LOCKDOWN_E_PAIRING_PROHIBITED_OVER_THIS_CONNECTION:
            return fail(AT_DEVICE_TRUST_DENIED,error,"The iPhone did not allow this Mac to connect.");
        case LOCKDOWN_E_MUX_ERROR:
            return fail(AT_DEVICE_UNAVAILABLE,error,"The iPhone is no longer connected over USB.");
        case LOCKDOWN_E_RECEIVE_TIMEOUT:
            return fail(AT_DEVICE_TIMEOUT,error,"The iPhone did not respond in time.");
        default:
            return fail(AT_DEVICE_SERVICE_ERROR,error,"The iPhone service could not be opened. Unlock and reconnect the device.");
    }
}
static ATDeviceResult open_device(const char *udid, idevice_t *device, lockdownd_client_t *lockdown, char **error) {
    *device = NULL; *lockdown = NULL;
    if (!valid_string(udid)) return fail(AT_DEVICE_INVALID_ARGUMENT,error,"A specific USB device is required.");
    if (idevice_new_with_options(device,udid,IDEVICE_LOOKUP_USBMUX) != IDEVICE_E_SUCCESS)
        return fail(AT_DEVICE_UNAVAILABLE,error,"The selected iPhone is not connected over USB.");
    lockdownd_error_t rc = lockdownd_client_new_with_handshake(*device,lockdown,AT_LABEL);
    if (rc != LOCKDOWN_E_SUCCESS) {
        if (*lockdown) { lockdownd_client_free(*lockdown); *lockdown=NULL; }
        idevice_free(*device); *device=NULL;
        return lockdown_failure(rc,error);
    }
    return AT_DEVICE_OK;
}
static ATDeviceResult encode_plist(plist_t value,char **xml,char **error) {
    char *allocated=NULL; uint32_t length=0;
    if (plist_to_xml(value,&allocated,&length) != PLIST_ERR_SUCCESS || !allocated)
        return fail(AT_DEVICE_IO_ERROR,error,"Could not encode the device response.");
    char *copy=malloc((size_t)length+1);
    if (copy) { memcpy(copy,allocated,length); copy[length]=0; }
    plist_mem_free(allocated);
    if (!copy) return fail(AT_DEVICE_OUT_OF_MEMORY,error,"Not enough memory for the device response.");
    *xml=copy; return AT_DEVICE_OK;
}
ATDeviceResult at_device_list_usb(char **out_xml,char **out_error) {
    if (out_error) *out_error=NULL;
    if (!out_xml) return fail(AT_DEVICE_INVALID_ARGUMENT,out_error,"An output buffer is required.");
    *out_xml=NULL;
    idevice_info_t *devices=NULL; int count=0;
    if (idevice_get_device_list_extended(&devices,&count) != IDEVICE_E_SUCCESS)
        return fail(AT_DEVICE_SERVICE_ERROR,out_error,"USB discovery is unavailable. Reconnect the iPhone.");
    plist_t array=plist_new_array();
    for (int i=0;i<count;i++) {
        if (!devices[i] || devices[i]->conn_type != CONNECTION_USBMUXD) continue;
        plist_t item=plist_new_dict();
        plist_dict_set_item(item,"UDID",plist_new_string(devices[i]->udid));
        plist_dict_set_item(item,"ConnectionType",plist_new_string("USB"));
        plist_array_append_item(array,item);
    }
    idevice_device_list_extended_free(devices);
    ATDeviceResult result=encode_plist(array,out_xml,out_error);
    plist_free(array); return result;
}
ATDeviceResult at_device_get_info(const char *udid,char **out_xml,char **out_error) {
    if (out_error) *out_error=NULL;
    if (!out_xml) return fail(AT_DEVICE_INVALID_ARGUMENT,out_error,"An output buffer is required.");
    *out_xml=NULL; idevice_t device=NULL; lockdownd_client_t lockdown=NULL;
    ATDeviceResult result=open_device(udid,&device,&lockdown,out_error);
    if (result != AT_DEVICE_OK) return result;
    plist_t info=plist_new_dict();
    const char *keys[]={"DeviceName","ProductType","ProductVersion","UniqueDeviceID","PasswordProtected",NULL};
    for (int i=0;keys[i];i++) {
        plist_t value=NULL;
        if (lockdownd_get_value(lockdown,NULL,keys[i],&value) == LOCKDOWN_E_SUCCESS && value)
            plist_dict_set_item(info,keys[i],value);
        else if (value) plist_free(value);
    }
    plist_t disk=NULL;
    if (lockdownd_get_value(lockdown,"com.apple.disk_usage",NULL,&disk)==LOCKDOWN_E_SUCCESS && disk) {
        const char *disk_keys[]={"TotalDataCapacity","TotalDataAvailable",NULL};
        for(int i=0;disk_keys[i];i++) {
            plist_t value=plist_dict_get_item(disk,disk_keys[i]);
            if (value) plist_dict_set_item(info,disk_keys[i],plist_copy(value));
        }
    }
    if(disk) plist_free(disk);
    /* A successful handshake is not proof that the phone has no passcode.
     * PasswordProtected describes passcode configuration, not current lock. */
    plist_dict_set_item(info,"ConnectionType",plist_new_string("USB"));
    if (!plist_dict_get_item(info,"UniqueDeviceID")) plist_dict_set_item(info,"UniqueDeviceID",plist_new_string(udid));
    result=encode_plist(info,out_xml,out_error);
    plist_free(info); lockdownd_client_free(lockdown); idevice_free(device);
    return result;
}
static ATDeviceResult start_installation_proxy(idevice_t device,lockdownd_client_t lockdown,instproxy_client_t *client,char **error) {
    lockdownd_service_descriptor_t service=NULL;
    lockdownd_error_t rc=lockdownd_start_service(lockdown,INSTPROXY_SERVICE_NAME,&service);
    if(rc != LOCKDOWN_E_SUCCESS) { if(service)lockdownd_service_descriptor_free(service); return lockdown_failure(rc,error); }
    instproxy_error_t ip=instproxy_client_new(device,service,client);
    lockdownd_service_descriptor_free(service);
    if(ip != INSTPROXY_E_SUCCESS) return fail(AT_DEVICE_SERVICE_ERROR,error,"The app installation service could not be opened.");
    return AT_DEVICE_OK;
}
static plist_t lookup_options(void) {
    plist_t opts=instproxy_client_options_new();
    plist_dict_set_item(opts,"ApplicationType",plist_new_string("User"));
    plist_dict_set_item(opts,"ShowPlaceholders",plist_new_bool(1));
    instproxy_client_options_set_return_attributes(opts,"CFBundleIdentifier","CFBundleDisplayName","CFBundleName","CFBundleShortVersionString","CFBundleVersion","IsDemotedApp","ApplicationType","iTunesMetadata","MinimumOSVersion","UIDeviceFamily",NULL);
    return opts;
}
static ATDeviceResult lookup_apps(const char *udid,const char *bundle,char **out_xml,char **out_error) {
    if (out_error) *out_error=NULL;
    if (!out_xml) return fail(AT_DEVICE_INVALID_ARGUMENT,out_error,"An output buffer is required.");
    *out_xml=NULL; idevice_t device=NULL; lockdownd_client_t lockdown=NULL; instproxy_client_t client=NULL;
    plist_t opts=NULL,apps=NULL;
    ATDeviceResult result=open_device(udid,&device,&lockdown,out_error);
    if(result != AT_DEVICE_OK) return result;
    result=start_installation_proxy(device,lockdown,&client,out_error);
    lockdownd_client_free(lockdown); lockdown=NULL;
    if(result != AT_DEVICE_OK) goto done;
    opts=lookup_options();
    const char *bundles[]={bundle,NULL};
    instproxy_error_t ip=instproxy_lookup(client,bundle?bundles:NULL,opts,&apps);
    if(ip != INSTPROXY_E_SUCCESS || !apps || plist_get_node_type(apps) != PLIST_DICT) {
        result=fail(AT_DEVICE_SERVICE_ERROR,out_error,"The iPhone did not return its app list. Unlock it and try again."); goto done;
    }
    if(bundle && !plist_dict_get_item(apps,bundle)) { result=fail(AT_DEVICE_NOT_FOUND,out_error,"The requested application is not present on this iPhone."); goto done; }
    result=encode_plist(apps,out_xml,out_error);
done:
    if(apps) plist_free(apps);
    if(opts) instproxy_client_options_free(opts);
    if(client) instproxy_client_free(client);
    if(lockdown) lockdownd_client_free(lockdown);
    if(device) idevice_free(device);
    return result;
}
ATDeviceResult at_device_lookup_apps(const char *udid,char **out_xml,char **out_error) { return lookup_apps(udid,NULL,out_xml,out_error); }
ATDeviceResult at_device_readback_app(const char *udid,const char *bundle_id,char **out_xml,char **out_error) {
    if(!valid_string(bundle_id)) { if(out_xml)*out_xml=NULL; if(out_error)*out_error=NULL; return fail(AT_DEVICE_INVALID_ARGUMENT,out_error,"A bundle identifier is required."); }
    return lookup_apps(udid,bundle_id,out_xml,out_error);
}
ATDeviceResult at_device_get_icon(const char *udid,const char *bundle_id,uint8_t **out_png,size_t *out_size,char **out_error) {
    if(out_error)*out_error=NULL;
    if(out_png)*out_png=NULL;
    if(out_size)*out_size=0;
    if(!out_png || !out_size || !valid_string(bundle_id)) return fail(AT_DEVICE_INVALID_ARGUMENT,out_error,"An app and icon output are required.");
    idevice_t device=NULL; lockdownd_client_t lockdown=NULL; lockdownd_service_descriptor_t service=NULL; sbservices_client_t client=NULL;
    ATDeviceResult result=open_device(udid,&device,&lockdown,out_error);
    if(result != AT_DEVICE_OK) return result;
    lockdownd_error_t ld=lockdownd_start_service(lockdown,SBSERVICES_SERVICE_NAME,&service);
    if(ld != LOCKDOWN_E_SUCCESS) { result=lockdown_failure(ld,out_error); goto done; }
    if(sbservices_client_new(device,service,&client) != SBSERVICES_E_SUCCESS) { result=fail(AT_DEVICE_SERVICE_ERROR,out_error,"The icon service is unavailable."); goto done; }
    char *png=NULL; uint64_t size=0;
    if(sbservices_get_icon_pngdata(client,bundle_id,&png,&size) != SBSERVICES_E_SUCCESS || !png || size==0 || size>16*1024*1024) {
        free(png); result=fail(AT_DEVICE_NOT_FOUND,out_error,"No icon is available for this application."); goto done;
    }
    *out_png=(uint8_t *)png; *out_size=(size_t)size;
done:
    if(client) sbservices_client_free(client);
    if(service) lockdownd_service_descriptor_free(service);
    if(lockdown) lockdownd_client_free(lockdown);
    if(device) idevice_free(device);
    return result;
}

struct ATDeviceListener {
    idevice_subscription_context_t subscription;
    ATDeviceEventCallback callback;
    void *context;
    pthread_mutex_t mutex;
    pthread_cond_t idle;
    unsigned callbacks;
    int stopped;
};
static void device_event(const idevice_event_t *event,void *raw) {
    ATDeviceListener *listener=raw;
    if(!event || event->conn_type != CONNECTION_USBMUXD) return;
    pthread_mutex_lock(&listener->mutex);
    if(listener->stopped) { pthread_mutex_unlock(&listener->mutex); return; }
    listener->callbacks++;
    pthread_mutex_unlock(&listener->mutex);
    listener->callback((int)event->event,event->udid,listener->context);
    pthread_mutex_lock(&listener->mutex);
    listener->callbacks--;
    pthread_cond_broadcast(&listener->idle);
    pthread_mutex_unlock(&listener->mutex);
}
ATDeviceResult at_device_events_start(ATDeviceEventCallback callback,void *context,ATDeviceListener **out_listener,char **out_error) {
    if(out_error)*out_error=NULL;
    if(out_listener)*out_listener=NULL;
    if(!callback || !out_listener) return fail(AT_DEVICE_INVALID_ARGUMENT,out_error,"A device event callback is required.");
    ATDeviceListener *listener=calloc(1,sizeof(*listener));
    if(!listener) return fail(AT_DEVICE_OUT_OF_MEMORY,out_error,"Could not start device discovery.");
    pthread_mutex_init(&listener->mutex,NULL); pthread_cond_init(&listener->idle,NULL);
    listener->callback=callback; listener->context=context;
    if(idevice_events_subscribe(&listener->subscription,device_event,listener) != IDEVICE_E_SUCCESS) {
        pthread_cond_destroy(&listener->idle); pthread_mutex_destroy(&listener->mutex); free(listener);
        return fail(AT_DEVICE_SERVICE_ERROR,out_error,"USB connection events are unavailable.");
    }
    *out_listener=listener; return AT_DEVICE_OK;
}
void at_device_events_stop(ATDeviceListener *listener) {
    if(!listener)return;
    pthread_mutex_lock(&listener->mutex); listener->stopped=1; pthread_mutex_unlock(&listener->mutex);
    idevice_events_unsubscribe(listener->subscription);
    pthread_mutex_lock(&listener->mutex);
    while(listener->callbacks) pthread_cond_wait(&listener->idle,&listener->mutex);
    pthread_mutex_unlock(&listener->mutex);
    pthread_cond_destroy(&listener->idle); pthread_mutex_destroy(&listener->mutex); free(listener);
}

typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t changed;
    int finished;
    int success;
    int disconnected;
    const char *udid;
    char error_name[128];
    ATDeviceProgressCallback callback;
    void *context;
} InstallState;
static void install_device_event(const idevice_event_t *event,void *raw) {
    InstallState *state=raw;
    if(!event || event->event!=IDEVICE_DEVICE_REMOVE || event->conn_type!=CONNECTION_USBMUXD || strcmp(event->udid,state->udid)!=0)return;
    pthread_mutex_lock(&state->mutex);
    state->disconnected=1; state->finished=1; state->success=0;
    pthread_cond_broadcast(&state->changed);
    pthread_mutex_unlock(&state->mutex);
}
static void sanitized_name(char *dest,size_t capacity,const char *source) {
    size_t written=0;
    for(size_t i=0;source && source[i] && written+1<capacity;i++) {
        unsigned char c=(unsigned char)source[i];
        if((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'||c=='-'||c==' ')dest[written++]=(char)c;
    }
    dest[written]=0;
}
static void installation_status(plist_t command,plist_t status,void *raw) {
    (void)command;
    InstallState *state=raw;
    char *name=NULL,*error_name=NULL; uint64_t error_code=0;
    instproxy_status_get_name(status,&name);
    instproxy_error_t error=instproxy_status_get_error(status,&error_name,NULL,&error_code);
    int percent=-1; instproxy_status_get_percent_complete(status,&percent);
    if(percent<0 || percent>100)percent=-1;
    char safe_status[128]; sanitized_name(safe_status,sizeof(safe_status),name?name:"Installing");
    if(state->callback)state->callback("installing",percent,safe_status,state->context);
    pthread_mutex_lock(&state->mutex);
    if(error != INSTPROXY_E_SUCCESS || error_name) {
        sanitized_name(state->error_name,sizeof(state->error_name),error_name?error_name:"DeviceInstallationError");
        state->success=0; state->finished=1;
    } else if(name && strcmp(name,"Complete")==0) { state->success=1; state->finished=1; }
    pthread_cond_broadcast(&state->changed);
    pthread_mutex_unlock(&state->mutex);
    free(name); free(error_name);
}
static ATDeviceResult wait_installation(instproxy_client_t client,const char *udid,const char *path,plist_t options,int uninstall,ATDeviceProgressCallback callback,void *context,char **error) {
    InstallState state={0};
    pthread_mutex_init(&state.mutex,NULL); pthread_cond_init(&state.changed,NULL);
    state.callback=callback; state.context=context; state.udid=udid;
    idevice_subscription_context_t subscription=NULL;
    idevice_events_subscribe(&subscription,install_device_event,&state);
    instproxy_error_t ip=uninstall ? instproxy_uninstall(client,path,options,installation_status,&state) : instproxy_install(client,path,options,installation_status,&state);
    ATDeviceResult result=AT_DEVICE_OK;
    if(ip != INSTPROXY_E_SUCCESS) result=fail(AT_DEVICE_INSTALL_FAILED,error,"The iPhone did not accept the app operation.");
    else {
        struct timespec deadline; clock_gettime(CLOCK_REALTIME,&deadline); deadline.tv_sec+=AT_OPERATION_TIMEOUT_SECONDS;
        pthread_mutex_lock(&state.mutex);
        while(!state.finished) {
            int rc=pthread_cond_timedwait(&state.changed,&state.mutex,&deadline);
            if(rc==ETIMEDOUT)break;
        }
        if(!state.finished) result=fail(AT_DEVICE_TIMEOUT,error,"No terminal installation result arrived. Reconnect the same iPhone and check its app list before retrying.");
        else if(state.disconnected) result=fail(AT_DEVICE_UNAVAILABLE,error,"The target iPhone disconnected. Reconnect the same device and check its app list before retrying.");
        else if(!state.success) {
            char message[256];
            snprintf(message,sizeof(message),"The iPhone rejected the operation: %s. Check its app list before retrying.",state.error_name[0]?state.error_name:"DeviceInstallationError");
            result=fail(AT_DEVICE_INSTALL_FAILED,error,message);
        }
        pthread_mutex_unlock(&state.mutex);
    }
    if(subscription)idevice_events_unsubscribe(subscription);
    /* client_free stops/joins the status worker before its stack context dies. */
    instproxy_client_free(client);
    pthread_cond_destroy(&state.changed); pthread_mutex_destroy(&state.mutex);
    return result;
}

/* Read bounded licensing/install metadata in memory. Do not extract archive
 * entries to disk. This mirrors the public installation_proxy contract, not
 * ideviceinstaller's GPL implementation. System libarchive is supplied by macOS. */
static struct archive *open_zip_fd(int fd) {
    if(lseek(fd,0,SEEK_SET)<0)return NULL;
    struct archive *archive=archive_read_new();
    if(!archive)return NULL;
    archive_read_support_format_zip(archive);
    if(archive_read_open_fd(archive,fd,65536)!=ARCHIVE_OK) { archive_read_free(archive); return NULL; }
    return archive;
}
static unsigned char *read_archive_entry(struct archive *archive,struct archive_entry *entry,size_t *length) {
    int64_t declared=archive_entry_size(entry);
    if(declared<=0 || declared>AT_MAX_INSTALL_METADATA)return NULL;
    unsigned char *buffer=malloc((size_t)declared);
    if(!buffer)return NULL;
    size_t total=0;
    while(total<(size_t)declared) {
        la_ssize_t count=archive_read_data(archive,buffer+total,(size_t)declared-total);
        if(count<=0) { free(buffer); return NULL; }
        total+=(size_t)count;
    }
    *length=total; return buffer;
}
static int primary_info_path(const char *name) {
    if(!name || strncmp(name,"Payload/",8)!=0)return 0;
    const char *slash=strchr(name+8,'/');
    return slash && (size_t)(slash-name)>12 && strncmp(slash-4,".app",4)==0 && strcmp(slash,"/Info.plist")==0;
}
static ATDeviceResult install_options_from_archive(int fd,plist_t *out_options,char **error) {
    struct archive *archive=open_zip_fd(fd);
    if(!archive)return fail(AT_DEVICE_IO_ERROR,error,"The IPA archive could not be opened.");
    plist_t options=instproxy_client_options_new(),info=NULL;
    char *app_directory=NULL,*executable=NULL,*bundle=NULL;
    struct archive_entry *entry=NULL;
    ATDeviceResult result=AT_DEVICE_OK; int primary_count=0,scan=ARCHIVE_OK;
    while((scan=archive_read_next_header(archive,&entry))==ARCHIVE_OK) {
        const char *name=archive_entry_pathname(entry);
        if(name && strcmp(name,"iTunesMetadata.plist")==0) {
            size_t length=0; unsigned char *data=read_archive_entry(archive,entry,&length);
            plist_t parsed=NULL;
            if(data)plist_from_memory((const char *)data,(uint32_t)length,&parsed,NULL);
            if(parsed && plist_get_node_type(parsed)==PLIST_DICT)plist_dict_set_item(options,"iTunesMetadata",plist_new_data((const char *)data,length));
            if(parsed)plist_free(parsed);
            free(data);
        } else if(primary_info_path(name)) {
            primary_count++;
            if(primary_count>1) { result=fail(AT_DEVICE_IO_ERROR,error,"The IPA contains multiple primary applications."); break; }
            size_t length=0; unsigned char *data=read_archive_entry(archive,entry,&length);
            if(data)plist_from_memory((const char *)data,(uint32_t)length,&info,NULL);
            free(data);
            if(!info || plist_get_node_type(info)!=PLIST_DICT) { result=fail(AT_DEVICE_IO_ERROR,error,"The IPA application metadata is invalid."); break; }
            app_directory=strndup(name,strlen(name)-strlen("Info.plist"));
            plist_get_string_val(plist_dict_get_item(info,"CFBundleExecutable"),&executable);
            plist_get_string_val(plist_dict_get_item(info,"CFBundleIdentifier"),&bundle);
        } else archive_read_data_skip(archive);
    }
    archive_read_free(archive); archive=NULL;
    if(result!=AT_DEVICE_OK)goto done;
    if(scan!=ARCHIVE_EOF || primary_count!=1 || !valid_string(bundle) || !valid_string(executable) || !app_directory || strchr(executable,'/')) { result=fail(AT_DEVICE_IO_ERROR,error,"The IPA has no valid primary application metadata."); goto done; }
    plist_dict_set_item(options,"CFBundleIdentifier",plist_new_string(bundle));
    size_t path_length=strlen(app_directory)+strlen("SC_Info/")+strlen(executable)+strlen(".sinf")+1;
    char *sinf_path=malloc(path_length);
    if(!sinf_path) { result=fail(AT_DEVICE_OUT_OF_MEMORY,error,"Not enough memory to prepare installation."); goto done; }
    snprintf(sinf_path,path_length,"%sSC_Info/%s.sinf",app_directory,executable);
    archive=open_zip_fd(fd);
    if(!archive) { free(sinf_path); result=fail(AT_DEVICE_IO_ERROR,error,"The IPA archive could not be read again."); goto done; }
    while(archive_read_next_header(archive,&entry)==ARCHIVE_OK) {
        const char *name=archive_entry_pathname(entry);
        if(name && strcmp(name,sinf_path)==0) {
            size_t length=0; unsigned char *data=read_archive_entry(archive,entry,&length);
            if(data)plist_dict_set_item(options,"ApplicationSINF",plist_new_data((const char *)data,length));
            free(data); break;
        }
        archive_read_data_skip(archive);
    }
    free(sinf_path);
done:
    if(archive)archive_read_free(archive);
    if(info)plist_free(info);
    free(app_directory); free(executable); free(bundle);
    if(lseek(fd,0,SEEK_SET)<0 && result==AT_DEVICE_OK)result=fail(AT_DEVICE_IO_ERROR,error,"The IPA file is no longer readable.");
    if(result==AT_DEVICE_OK)*out_options=options;
    else instproxy_client_options_free(options);
    return result;
}
ATDeviceResult at_device_install_ipa(const char *udid,const char *local_ipa_path,ATDeviceProgressCallback callback,void *context,char **out_error) {
    if(out_error)*out_error=NULL;
    if(!valid_string(local_ipa_path) || local_ipa_path[0]!='/') return fail(AT_DEVICE_INVALID_ARGUMENT,out_error,"An absolute validated IPA path is required.");
    int fd=open(local_ipa_path,O_RDONLY|O_NOFOLLOW);
    struct stat st;
    if(fd<0)return fail(AT_DEVICE_IO_ERROR,out_error,"The IPA file could not be opened.");
    if(fstat(fd,&st)!=0 || !S_ISREG(st.st_mode) || st.st_size<=0) { close(fd); return fail(AT_DEVICE_IO_ERROR,out_error,"The IPA must be a nonempty regular file."); }
    plist_t options=NULL;
    ATDeviceResult result=install_options_from_archive(fd,&options,out_error);
    if(result!=AT_DEVICE_OK) { close(fd); return result; }
    idevice_t device=NULL; lockdownd_client_t lockdown=NULL; afc_client_t afc=NULL; instproxy_client_t proxy=NULL;
    lockdownd_service_descriptor_t service=NULL; uint64_t handle=0; char *buffer=NULL; int staged=0;
    char remote[128]; unsigned char nonce[16]; arc4random_buf(nonce,sizeof(nonce));
    snprintf(remote,sizeof(remote),"PublicStaging/AppTransfer-%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x.ipa",nonce[0],nonce[1],nonce[2],nonce[3],nonce[4],nonce[5],nonce[6],nonce[7],nonce[8],nonce[9],nonce[10],nonce[11],nonce[12],nonce[13],nonce[14],nonce[15]);
    result=open_device(udid,&device,&lockdown,out_error);
    if(result != AT_DEVICE_OK)goto done;
    result=start_installation_proxy(device,lockdown,&proxy,out_error);
    if(result != AT_DEVICE_OK)goto done;
    lockdownd_error_t ld=lockdownd_start_service(lockdown,AFC_SERVICE_NAME,&service);
    if(ld != LOCKDOWN_E_SUCCESS) { result=lockdown_failure(ld,out_error); goto done; }
    if(afc_client_new(device,service,&afc) != AFC_E_SUCCESS) { result=fail(AT_DEVICE_SERVICE_ERROR,out_error,"The iPhone file transfer service could not be opened."); goto done; }
    lockdownd_service_descriptor_free(service); service=NULL;
    lockdownd_client_free(lockdown); lockdown=NULL;
    /* Only our unique staged file is removed; never recursively remove staging. */
    afc_make_directory(afc,"PublicStaging");
    if(afc_file_open(afc,remote,AFC_FOPEN_WRONLY,&handle) != AFC_E_SUCCESS) { result=fail(AT_DEVICE_IO_ERROR,out_error,"The IPA could not be staged on the iPhone. Check available storage."); goto done; }
    staged=1; buffer=malloc(AT_UPLOAD_CHUNK);
    if(!buffer) { result=fail(AT_DEVICE_OUT_OF_MEMORY,out_error,"Not enough memory to upload the IPA."); goto done; }
    uint64_t total=0; int last_percent=-1;
    if(callback && callback("uploading",0,"Uploading IPA",context)) { result=fail(AT_DEVICE_CANCELED,out_error,"Upload canceled before installation."); goto done; }
    for(;;) {
        ssize_t count=read(fd,buffer,AT_UPLOAD_CHUNK);
        if(count<0 && errno==EINTR)continue;
        if(count<0) { result=fail(AT_DEVICE_IO_ERROR,out_error,"The IPA could not be read completely."); goto done; }
        if(count==0)break;
        uint32_t offset=0;
        while(offset<(uint32_t)count) {
            uint32_t written=0;
            if(afc_file_write(afc,handle,buffer+offset,(uint32_t)count-offset,&written) != AFC_E_SUCCESS || !written || written>(uint32_t)count-offset) { result=fail(AT_DEVICE_IO_ERROR,out_error,"USB upload failed. Reconnect the same iPhone and retry."); goto done; }
            offset+=written; total+=written;
        }
        int percent=(int)((long double)total*100/(long double)st.st_size);
        if(percent>100)percent=100;
        if(callback && percent != last_percent) {
            last_percent=percent;
            if(callback("uploading",percent,"Uploading IPA",context)) { result=fail(AT_DEVICE_CANCELED,out_error,"Upload canceled before installation."); goto done; }
        }
    }
    if(total!=(uint64_t)st.st_size) { result=fail(AT_DEVICE_IO_ERROR,out_error,"The IPA changed during upload. Validate it again before retrying."); goto done; }
    if(afc_file_close(afc,handle) != AFC_E_SUCCESS) { handle=0; result=fail(AT_DEVICE_IO_ERROR,out_error,"The iPhone did not finish writing the IPA."); goto done; }
    handle=0; close(fd); fd=-1;
    if(callback)callback("installing",-1,"Installing IPA",context);
    result=wait_installation(proxy,udid,remote,options,0,callback,context,out_error); proxy=NULL;
done:
    if(handle && afc)afc_file_close(afc,handle);
    if(staged && afc)afc_remove_path(afc,remote);
    if(proxy)instproxy_client_free(proxy);
    if(afc)afc_client_free(afc);
    if(service)lockdownd_service_descriptor_free(service);
    if(lockdown)lockdownd_client_free(lockdown);
    if(device)idevice_free(device);
    if(fd>=0)close(fd);
    free(buffer); if(options)instproxy_client_options_free(options); return result;
}
ATDeviceResult at_device_uninstall_app(const char *udid,const char *bundle_id,ATDeviceProgressCallback callback,void *context,char **out_error) {
    if(out_error)*out_error=NULL;
    if(!valid_string(bundle_id))return fail(AT_DEVICE_INVALID_ARGUMENT,out_error,"A specific application is required.");
    idevice_t device=NULL; lockdownd_client_t lockdown=NULL; instproxy_client_t proxy=NULL;
    ATDeviceResult result=open_device(udid,&device,&lockdown,out_error);
    if(result != AT_DEVICE_OK)return result;
    result=start_installation_proxy(device,lockdown,&proxy,out_error);
    lockdownd_client_free(lockdown);
    if(result==AT_DEVICE_OK)result=wait_installation(proxy,udid,bundle_id,NULL,1,callback,context,out_error);
    else if(proxy)instproxy_client_free(proxy);
    idevice_free(device); return result;
}
