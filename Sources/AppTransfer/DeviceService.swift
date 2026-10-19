import Foundation
import DeviceBridge
import AppTransferCore

private final class InstallContext {
    let cancellation:CancellationFlag
    let progress:@Sendable(JobStage,Double?)->Void
    init(_ cancellation:CancellationFlag,_ progress:@escaping @Sendable(JobStage,Double?)->Void){self.cancellation=cancellation;self.progress=progress}
}

final class DeviceService:DeviceBackend,@unchecked Sendable {
    private let queue=DispatchQueue(label:"com.apptransfer.devices",qos:.userInitiated)
    private var listener:OpaquePointer?
    private let eventLock=NSLock()
    private var eventHandler:(@Sendable()->Void)?
    private var known:[String:Phone]=[:]
    init(){var error:UnsafeMutablePointer<CChar>?;let context=Unmanaged.passUnretained(self).toOpaque();let result=at_device_events_start({_,_,context in guard let context else{return};let service=Unmanaged<DeviceService>.fromOpaque(context).takeUnretainedValue();service.eventLock.lock();let handler=service.eventHandler;service.eventLock.unlock();handler?()},context,&listener,&error);at_device_free(error);if result != AT_DEVICE_OK {listener=nil}}
    deinit {if let listener {at_device_events_stop(listener)}}
    func onChange(_ handler:@escaping @Sendable()->Void){eventLock.lock();eventHandler=handler;eventLock.unlock()}
    private func perform<T>(_ body:@escaping()throws->T) async throws -> T {try await withCheckedThrowingContinuation{continuation in queue.async{do{continuation.resume(returning:try body())}catch{continuation.resume(throwing:error)}}}}
    private func plist(_ call:(UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>)->ATDeviceResult) throws -> Any {
        var xml:UnsafeMutablePointer<CChar>?,message:UnsafeMutablePointer<CChar>?
        let result=call(&xml,&message);defer{at_device_free(xml);at_device_free(message)}
        guard result==AT_DEVICE_OK,let xml else {throw failure(result,message:message)}
        return try PropertyListSerialization.propertyList(from:Data(String(cString:xml).utf8),format:nil)
    }
    private func failure(_ result:ATDeviceResult,message:UnsafeMutablePointer<CChar>?) -> AppFailure {
        let code:String
        switch result {case AT_DEVICE_LOCKED:code="deviceLocked";case AT_DEVICE_TRUST_PENDING,AT_DEVICE_TRUST_DENIED:code="trustRequired";case AT_DEVICE_UNAVAILABLE,AT_DEVICE_NOT_FOUND:code="deviceUnavailable";case AT_DEVICE_CANCELED:code="canceled";case AT_DEVICE_TIMEOUT:code="deviceTimeout";case AT_DEVICE_INSTALL_FAILED:code="installationFailed";default:code="deviceError"}
        return AppFailure(code,message.map{String(cString:$0)} ?? "The iPhone operation failed.")
    }
    func devices() async throws -> [Phone] {try await perform{[self] in
        let raw=try plist{at_device_list_usb($0,$1)} as? [[String:Any]] ?? []
        return raw.compactMap{entry -> Phone? in
            guard let id=entry["UDID"] as? String else{return nil}
            do {
                let info=try plist{at_device_get_info(id,$0,$1)} as? [String:Any] ?? [:]
                let phone=Phone(id:id,name:info["DeviceName"] as? String ?? "iPhone",model:friendlyModel(info["ProductType"] as? String ?? "iPhone"),iOS:info["ProductVersion"] as? String ?? "",freeBytes:(info["TotalDataAvailable"] as? NSNumber)?.int64Value,state:"connected")
                known[id]=phone;return phone
            } catch {
                var phone=known[id] ?? Phone(id:id,name:"iPhone · \(id.suffix(4))",model:"iPhone",iOS:"")
                phone.state=(error as? AppFailure)?.code ?? "deviceError";return phone
            }
        }.sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}
    }}
    func applications(on deviceID:String) async throws -> [AppDescriptor] {try await perform{[self] in
        let apps=try plist{at_device_lookup_apps(deviceID,$0,$1)} as? [String:[String:Any]] ?? [:]
        return apps.map{bundle,raw in
            var meta:[String:Any]=[:]
            if let bytes=raw["iTunesMetadata"] as? Data {meta=(try? PropertyListSerialization.propertyList(from:bytes,format:nil)) as? [String:Any] ?? [:]}
            else if let value=raw["iTunesMetadata"] as? [String:Any] {meta=value}
            let download=meta["com.apple.iTunesStore.downloadInfo"] as? [String:Any]
            let account=download?["accountInfo"] as? [String:Any]
            return AppDescriptor(bundleID:bundle,name:raw["CFBundleDisplayName"] as? String ?? meta["itemName"] as? String ?? raw["CFBundleName"] as? String ?? bundle,version:string(raw["CFBundleShortVersionString"]) ?? string(meta["bundleShortVersionString"]) ?? "",build:string(raw["CFBundleVersion"]) ?? string(meta["bundleVersion"]) ?? "",storeItemID:(meta["itemId"] as? NSNumber)?.int64Value,externalVersionID:string(meta["softwareVersionExternalIdentifier"]),ownerEmail:account?["AppleID"] as? String,offloaded:(raw["IsDemotedApp"] as? Bool) ?? false,testFlight:meta["betaExternalVersionIdentifier"] != nil || (meta["sourceApp"] as? String)=="com.apple.TestFlight")
        }.sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}
    }}
    func icon(bundleID:String,on deviceID:String) async throws -> Data {try await perform{[self] in
        var bytes:UnsafeMutablePointer<UInt8>?,count=0,message:UnsafeMutablePointer<CChar>?
        let result=at_device_get_icon(deviceID,bundleID,&bytes,&count,&message);defer{at_device_free(bytes);at_device_free(message)}
        guard result==AT_DEVICE_OK,let bytes,count>0 else {throw failure(result,message:message)}
        return Data(bytes:bytes,count:count)
    }}
    func install(_ url:URL,on deviceID:String,cancellation:CancellationFlag,progress:@escaping @Sendable(JobStage,Double?)->Void) async throws {try await perform{[self] in
        let context=Unmanaged.passRetained(InstallContext(cancellation,progress));defer{context.release()}
        var message:UnsafeMutablePointer<CChar>?;defer{at_device_free(message)}
        let result=at_device_install_ipa(deviceID,url.path,{stage,percent,_,opaque in
            guard let opaque else{return 0};let context=Unmanaged<InstallContext>.fromOpaque(opaque).takeUnretainedValue()
            let phase=stage.map{String(cString:$0)} ?? "installing"
            context.progress(phase=="uploading" ? .uploading:.installing,percent<0 ? nil:Double(percent)/100)
            return context.cancellation.requested && phase=="uploading" ? 1:0
        },context.toOpaque(),&message)
        guard result==AT_DEVICE_OK else{throw failure(result,message:message)}
    }}
    private func string(_ value:Any?)->String?{if let s=value as? String{return s};if let n=value as? NSNumber{return n.stringValue};return nil}
    private func friendlyModel(_ model:String)->String{["iPhone15,2":"iPhone 14 Pro","iPhone15,3":"iPhone 14 Pro Max","iPhone14,7":"iPhone 14","iPhone14,8":"iPhone 14 Plus","iPhone16,1":"iPhone 15 Pro","iPhone16,2":"iPhone 15 Pro Max","iPhone15,4":"iPhone 15","iPhone15,5":"iPhone 15 Plus","iPhone17,1":"iPhone 16 Pro","iPhone17,2":"iPhone 16 Pro Max","iPhone17,3":"iPhone 16","iPhone17,4":"iPhone 16 Plus","iPhone18,1":"iPhone 17 Pro","iPhone18,2":"iPhone 17 Pro Max","iPhone18,3":"iPhone 17"][model] ?? model}
}
