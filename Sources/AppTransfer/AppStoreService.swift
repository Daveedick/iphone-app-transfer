import Foundation
import AppTransferCore

actor AppStoreService:StoreBackend {
    private struct Pending {
        var continuation:CheckedContinuation<[String:Any],Error>
        var event:(@Sendable(String,[String:Any])->Void)?
        var timeout:Task<Void,Never>?
    }
    private var process:Process?
    private var input:FileHandle?
    private var pending:[String:Pending]=[:]
    private var buffer=Data()
    private var downloadRequestID:String?
    private var starting=false
    private let readQueue=DispatchQueue(label:"com.apptransfer.appstore.read",qos:.utility)
    private var generation=UUID()
    private func helperURL() throws -> URL {
        if let path=ProcessInfo.processInfo.environment["APPTRANSFER_HELPER_PATH"] {return URL(fileURLWithPath:path)}
        let bundled=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/AppStoreBridge")
        if FileManager.default.isExecutableFile(atPath:bundled.path){return bundled}
        let development=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/helpers/AppStoreBridge")
        if !Bundle.main.bundleURL.pathExtension.elementsEqual("app"),FileManager.default.isExecutableFile(atPath:development.path){return development}
        throw AppFailure("helperUnavailable","The bundled App Store component is missing.")
    }
    private func startIfNeeded() throws {
        if process?.isRunning==true{return}
        let child=Process(),stdin=Pipe(),stdout=Pipe(),stderr=Pipe(),current=UUID()
        child.executableURL=try helperURL();child.standardInput=stdin;child.standardOutput=stdout;child.standardError=stderr
        // Never inherit a developer's standalone ipatool configuration.
        var environment=ProcessInfo.processInfo.environment
        environment.removeValue(forKey:"IPATOOL_HOME");environment.removeValue(forKey:"IPATOOL_LOG_LEVEL")
        child.environment=environment
        child.terminationHandler={[weak self] _ in Task{await self?.terminated(current)}}
        stderr.fileHandleForReading.readabilityHandler={handle in _=handle.availableData} // upstream diagnostics must not become an app log
        try child.run();process=child;input=stdin.fileHandleForWriting;generation=current;buffer=Data()
        let reader=stdout.fileHandleForReading
        readQueue.async{[weak self] in
            while true {let data=reader.availableData;if data.isEmpty{break};let semaphore=DispatchSemaphore(value:0);Task{await self?.receive(data,generation:current);semaphore.signal()};semaphore.wait()}
            try? reader.close()
        }
    }
    private func terminated(_ current:UUID){guard generation==current else{return};process=nil;input=nil;let entries=pending;pending.removeAll();for request in entries.values{request.timeout?.cancel();request.continuation.resume(throwing:AppFailure("helperUnavailable","The App Store component stopped. Retry the operation."))}}
    private func receive(_ data:Data,generation current:UUID) {
        guard current==generation else{return};buffer.append(data)
        if buffer.count>2*1024*1024 {process?.terminate();return}
        while let newline=buffer.firstIndex(of:10) {
            let line=buffer.prefix(upTo:newline);buffer.removeSubrange(...newline)
            guard let object=try? JSONSerialization.jsonObject(with:Data(line)) as? [String:Any],object["protocolVersion"] as? Int==1,let id=object["requestId"] as? String,let kind=object["event"] as? String,let request=pending[id] else{continue}
            let payload=object["payload"] as? [String:Any] ?? [:]
            request.event?(kind,payload)
            if ["ready","completed","failed","canceled","auth.succeeded"].contains(kind) {
                pending.removeValue(forKey:id);request.timeout?.cancel()
                if kind=="failed" {let error=object["error"] as? [String:Any] ?? [:];request.continuation.resume(throwing:AppFailure(normalizedCode(error["code"] as? String ?? "operationFailed"),error["message"] as? String ?? "The App Store request failed."))}
                else if kind=="canceled" {request.continuation.resume(throwing:AppFailure("canceled","Operation canceled."))}
                else {request.continuation.resume(returning:payload)}
            }
        }
    }
    private func normalizedCode(_ code:String)->String {
        switch code {case "license.required":return "licenseRequired";case "auth.required","auth.invalid_credentials","account.not_found","account.required":return "authenticationRequired";case "auth.expired","account.expired":return "sessionExpired";case "network.failed","network.timeout":return "network";case "version.unavailable":return "versionUnavailable";case "operation.canceled":return "canceled";default:return code}
    }
    private func request(_ command:String,_ payload:[String:Any]=[:],id:String=UUID().uuidString,event:(@Sendable(String,[String:Any])->Void)?=nil) async throws -> [String:Any] {
        try startIfNeeded()
        return try await withCheckedThrowingContinuation{continuation in
            let timeout=Task{[weak self] in try? await Task.sleep(nanoseconds:1_800_000_000_000);guard !Task.isCancelled else{return};await self?.timeout(id)}
            pending[id]=Pending(continuation:continuation,event:event,timeout:timeout)
            do {var data=try JSONSerialization.data(withJSONObject:["protocolVersion":1,"requestId":id,"command":command,"payload":payload]);data.append(10);try input?.write(contentsOf:data)}catch{pending.removeValue(forKey:id)?.timeout?.cancel();continuation.resume(throwing:error)}
        }
    }
    private func timeout(_ id:String) async {
        guard pending[id] != nil else{return}
        if var data=try? JSONSerialization.data(withJSONObject:["protocolVersion":1,"requestId":UUID().uuidString,"command":"operation.cancel","payload":["operationId":id]]){data.append(10);try? input?.write(contentsOf:data)}
        try? await Task.sleep(nanoseconds:2_000_000_000)
        // A request must not return while an untracked helper is still writing its IPA.
        // The termination callback resolves pending continuations after actual process exit.
        if pending[id] != nil {process?.terminate()}
    }
    func hello() async throws -> [String:Any] {try await request("hello")}
    func accounts() async throws -> [AppleAccount] {let value=try await request("account.list");return (value["accounts"] as? [[String:Any]] ?? []).compactMap(account)}
    private func account(_ value:[String:Any])->AppleAccount? {guard let id=value["id"] as? String,let email=value["email"] as? String else{return nil};return AppleAccount(id:id,email:email,name:value["name"] as? String,storefront:value["storefront"] as? String,authenticated:value["authenticated"] as? Bool ?? false)}
    func login(email:String,password:String,accountID:String?,event:@escaping @Sendable(String,[String:Any])->Void) async throws -> AppleAccount {
        var payload:[String:Any]=["email":email,"password":password];if let accountID{payload["accountId"]=accountID}
        let result=try await request("auth.begin",payload,event:event)
        guard let raw=result["account"] as? [String:Any],let account=account(raw) else{throw AppFailure("authenticationRequired","Apple did not confirm the account.")};return account
    }
    func submitCode(accountID:String,code:String) async throws{_ = try await request("auth.submitCode",["accountId":accountID,"code":code])}
    func cancelLogin(accountID:String) async{_ = try? await request("auth.cancel",["accountId":accountID])}
    func removeAccount(_ id:String) async throws{_ = try await request("account.remove",["accountId":id])}
    func versionInfo(app:AppDescriptor,accountID:String,latest:Bool) async throws -> AppDescriptor {
        guard let storeID=app.storeItemID else{throw AppFailure("unsupportedApp","Missing App Store identifier.")}
        var external=latest ? "":app.externalVersionID ?? ""
        if !latest && external.isEmpty {throw AppFailure("versionUnavailable","The source app has no exact App Store version identifier.")}
        if latest {let versions=try await request("app.versions",["accountId":accountID,"storeItemId":storeID,"bundleId":app.bundleID]);external=versions["latestExternalVersionId"] as? String ?? "";guard !external.isEmpty else{throw AppFailure("versionUnavailable","No downloadable version was offered by Apple.")}}
        let result=try await request("app.versionInfo",["accountId":accountID,"storeItemId":storeID,"bundleId":app.bundleID,"externalVersionId":external])
        var value=app;value.externalVersionID=result["externalVersionId"] as? String;value.version=result["version"] as? String ?? app.version
        if latest || value.version != app.version {value.build=""}
        return value
    }
    func download(app:AppDescriptor,accountID:String,to url:URL,progress:@escaping @Sendable(Double?)->Void) async throws {
        guard let storeID=app.storeItemID,let versionID=app.externalVersionID,!versionID.isEmpty else{throw AppFailure("unsupportedApp","Missing exact App Store version identifier.")}
        let id=UUID().uuidString;downloadRequestID=id;defer{downloadRequestID=nil}
        let result=try await request("app.download",["accountId":accountID,"storeItemId":storeID,"bundleId":app.bundleID,"externalVersionId":versionID,"outputPath":url.path],id:id){kind,payload in if kind=="download.progress" {progress(payload["fraction"] as? Double)}}
        guard result["destinationPath"] as? String==url.path else{throw AppFailure("invalidArchive","The App Store component returned an unexpected output path.")}
    }
    func cancelDownload() async{if let id=downloadRequestID {_ = try? await request("operation.cancel",["operationId":id])}}
    func shutdown(){input?.closeFile();process?.terminate();process=nil}
}
