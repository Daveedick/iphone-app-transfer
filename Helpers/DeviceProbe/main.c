/* Read-only bridge smoke check. Prints counts/model/iOS, never UDIDs, emails,
 * app names, raw inventory, or icon pixels. No install/uninstall call exists. */
#include "DeviceBridge.h"
#include <plist/plist.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void event(int kind,const char *udid,void *context) { (void)kind; (void)udid; (void)context; }
static plist_t parse(char *xml) {
    plist_t value=NULL;
    if(xml)plist_from_xml(xml,(uint32_t)strlen(xml),&value);
    return value;
}
int main(void) {
    char *xml=NULL,*error=NULL; ATDeviceListener *listener=NULL;
    ATDeviceResult subscription=at_device_events_start(event,NULL,&listener,&error);
    at_device_free(error); error=NULL;
    ATDeviceResult result=at_device_list_usb(&xml,&error);
    if(result!=AT_DEVICE_OK) {
        printf("discovery status=%d\n",result);
        at_device_free(error); at_device_events_stop(listener); return 1;
    }
    plist_t list=parse(xml); at_device_free(xml); xml=NULL;
    printf("discovery=ok usb_devices=%u hotplug_subscription=%d\n",plist_array_get_size(list),subscription);
    for(uint32_t i=0;i<plist_array_get_size(list);i++) {
        char *udid=NULL;
        plist_get_string_val(plist_dict_get_item(plist_array_get_item(list,i),"UDID"),&udid);
        result=at_device_get_info(udid,&xml,&error);
        if(result!=AT_DEVICE_OK) {
            printf("device_index=%u info_status=%d\n",i,result);
            at_device_free(error); error=NULL; free(udid); continue;
        }
        plist_t info=parse(xml); at_device_free(xml); xml=NULL;
        char *model=NULL,*version=NULL;
        plist_get_string_val(plist_dict_get_item(info,"ProductType"),&model);
        plist_get_string_val(plist_dict_get_item(info,"ProductVersion"),&version);
        printf("device_index=%u info=ok model=%s ios=%s\n",i,model?model:"unknown",version?version:"unknown");
        free(model); free(version); plist_free(info);
        result=at_device_lookup_apps(udid,&xml,&error);
        if(result!=AT_DEVICE_OK) {
            printf("device_index=%u lookup_status=%d\n",i,result);
            at_device_free(error); error=NULL; free(udid); continue;
        }
        plist_t apps=parse(xml); at_device_free(xml); xml=NULL;
        uint32_t count=plist_dict_get_size(apps),metadata=0,demoted=0;
        plist_dict_iter iterator=NULL; plist_dict_new_iter(apps,&iterator);
        char *key=NULL; plist_t app=NULL;
        while(iterator) {
            plist_dict_next_item(apps,iterator,&key,&app);
            if(!key)break;
            uint8_t is_demoted=0;
            plist_t item=plist_dict_get_item(app,"iTunesMetadata");
            if(item&&plist_get_node_type(item)==PLIST_DATA)metadata++;
            plist_get_bool_val(plist_dict_get_item(app,"IsDemotedApp"),&is_demoted);
            if(is_demoted)demoted++;
            free(key); key=NULL;
        }
        printf("device_index=%u lookup=ok apps=%u metadata=%u offloaded=%u\n",i,count,metadata,demoted);
        /* Test a targeted readback/icon only when Mail is already present. */
        const char *icon_bundle="ru.mail.mail";
        if(plist_dict_get_item(apps,icon_bundle)) {
            char *readback=NULL;
            result=at_device_readback_app(udid,icon_bundle,&readback,&error);
            printf("device_index=%u targeted_readback_status=%d\n",i,result);
            at_device_free(readback); at_device_free(error); error=NULL;
            uint8_t *png=NULL; size_t bytes=0;
            result=at_device_get_icon(udid,icon_bundle,&png,&bytes,&error);
            printf("device_index=%u icon_status=%d bytes=%zu\n",i,result,bytes);
            at_device_free(png); at_device_free(error); error=NULL;
        }
        free(iterator); plist_free(apps); free(udid);
    }
    plist_free(list); at_device_events_stop(listener);
    printf("subscription_cleanup=ok\n"); return 0;
}
