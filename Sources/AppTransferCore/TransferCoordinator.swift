import Foundation

public final class CancellationFlag: @unchecked Sendable {
    private let lock=NSLock()
    private var value=false
    public init() {}
    public var requested: Bool {lock.lock();defer{lock.unlock()};return value}
    public func cancel(){lock.lock();value=true;lock.unlock()}
}

public protocol DeviceBackend: Sendable {
    func devices() async throws -> [Phone]
    func applications(on deviceID:String) async throws -> [AppDescriptor]
    func install(_ url:URL,on deviceID:String,cancellation:CancellationFlag,progress:@escaping @Sendable(JobStage,Double?)->Void) async throws
}

public protocol StoreBackend: Sendable {
    func accounts() async throws -> [AppleAccount]
    func versionInfo(app:AppDescriptor,accountID:String,latest:Bool) async throws -> AppDescriptor
    func download(app:AppDescriptor,accountID:String,to url:URL,progress:@escaping @Sendable(Double?)->Void) async throws
    func cancelDownload() async
}

public struct QueueSnapshot:Sendable {
    public var jobs:[TransferJob]
    public var history:[ActivityEntry]
    public var paused:Bool
    public var running:Bool
    public var persistenceError:String?
}

public actor TransferCoordinator {
    private let device:any DeviceBackend
    private let store:any StoreBackend
    private let library:LibraryStore
    private let persistence:OperationStore
    private var jobs:[TransferJob]=[]
    private var history:[ActivityEntry]=[]
    private var paused=false
    private var worker:Task<Void,Never>?
    private var activeID:UUID?
    private var cancellation:CancellationFlag?
    private var persistenceError:String?
    public init(device:any DeviceBackend,store:any StoreBackend,library:LibraryStore,persistence:OperationStore){self.device=device;self.store=store;self.library=library;self.persistence=persistence}
    public func start() async throws {
        let saved=try await persistence.load();jobs=saved.jobs;history=saved.history;paused=saved.paused
        for i in jobs.indices where !jobs[i].stage.terminal && jobs[i].stage != .queued && !jobs[i].stage.waiting {jobs[i].stage = .interrupted;jobs[i].progress=nil;jobs[i].message="The previous operation was interrupted. Reconnect the device and retry to verify its state first."}
        await persist();pump()
    }
    public func snapshot() -> QueueSnapshot {QueueSnapshot(jobs:jobs,history:history,paused:paused,running:activeID != nil,persistenceError:persistenceError)}
    @discardableResult public func enqueue(_ job:TransferJob) async -> EnqueueOutcome {
        if let existing=jobs.first(where:{!$0.stage.terminal && $0.app.bundleID==job.app.bundleID && $0.app.version==job.app.version && $0.targetDeviceID==job.targetDeviceID && $0.accountID==job.accountID}) {return EnqueueOutcome(jobID:existing.id,inserted:false)}
        var accepted=job;accepted.lastQueuedAt=Date()
        jobs.append(accepted);await persist();pump()
        return EnqueueOutcome(jobID:accepted.id,inserted:true)
    }
    public func setPaused(_ value:Bool) async {paused=value;await persist();if !value {pump()}}
    public func cancel(_ id:UUID) async {
        guard let i=jobs.firstIndex(where:{$0.id==id}),!jobs[i].stage.terminal else{return}
        jobs[i].cancelRequested=true
        if id==activeID {
            cancellation?.cancel()
            if jobs[i].stage == .downloading {await store.cancelDownload()}
            if jobs[i].stage == .installing || jobs[i].stage == .verifying {paused=true;jobs[i].message="The device will finish its current installation before the queue stops."}
        } else {await complete(id,.canceled)}
        await persist()
    }
    @discardableResult public func retry(_ id:UUID) async -> Bool {
        guard id != activeID,let i=jobs.firstIndex(where:{$0.id==id}) else{return false}
        jobs[i].stage = .queued;jobs[i].cancelRequested=false;jobs[i].message=nil;jobs[i].errorCode=nil;jobs[i].progress=nil;jobs[i].lastQueuedAt=Date();await persist();pump()
        return true
    }
    public func assignAccount(_ id:UUID,account:AppleAccount) async {
        guard id != activeID,let i=jobs.firstIndex(where:{$0.id==id}) else{return}
        jobs[i].accountID=account.id;jobs[i].accountEmail=account.email;jobs[i].libraryID=nil;jobs[i].stage = .queued;jobs[i].errorCode=nil;jobs[i].message=nil;jobs[i].cancelRequested=false;await persist();pump()
    }
    public func acceptAlternative(_ id:UUID) async {
        guard let i=jobs.firstIndex(where:{$0.id==id}),let alternative=jobs[i].alternative,id != activeID else{return}
        jobs[i].app=alternative;jobs[i].alternative=nil;jobs[i].libraryID=nil;jobs[i].stage = .queued;jobs[i].errorCode=nil;jobs[i].message=nil;await persist();pump()
    }
    public func busyLibraryIDs() -> Set<UUID> {Set(jobs.filter{!$0.stage.terminal}.compactMap(\.libraryID))}
    public func removeLibraryItems(_ ids:Set<UUID>) async throws -> [LibraryItem] {
        let entries=await library.snapshot()
        var busy=busyLibraryIDs()
        // Resolving a matching archive and binding its ID cross actor boundaries.
        // Protect eligible cache entries before that binding as well.
        for job in jobs where !job.stage.terminal {
            for item in entries where item.accountID==job.accountID && item.app.sameBuild(as:job.app) {busy.insert(item.id)}
        }
        let removed=try await library.delete(ids:ids,busy:busy)
        for item in removed {history.append(ActivityEntry(appName:item.app.name,version:item.app.version,source:"Library",target:"Trash",message:"Removed from library; installed copies remain on devices."))}
        await persist();return removed
    }
    private func pump(){guard worker==nil,!paused else{return};worker=Task{await self.work()}}
    private func work() async {
        while !paused,let job=jobs.first(where:{$0.stage == .queued}) {
            activeID=job.id;cancellation=CancellationFlag();await run(job.id);activeID=nil;cancellation=nil
        }
        worker=nil
        if !paused,jobs.contains(where:{$0.stage == .queued}) {pump()}
    }
    private func current(_ id:UUID) -> TransferJob? {jobs.first{$0.id==id}}
    private func update(_ id:UUID,stage:JobStage?=nil,progress:Double?=nil,message:String?=nil,code:String?=nil) async {
        guard let i=jobs.firstIndex(where:{$0.id==id}) else{return};if let stage {jobs[i].stage=stage};jobs[i].progress=progress;jobs[i].message=message;jobs[i].errorCode=code;jobs[i].updated=Date()
        if progress==nil || progress==1 {await persist()}
    }
    private func reportProgress(_ id:UUID,stage:JobStage,progress:Double?) async {
        guard activeID==id,let i=jobs.firstIndex(where:{$0.id==id}),!jobs[i].stage.terminal else{return}
        let current=jobs[i].stage
        guard current==stage || (current == .uploading && stage == .installing) else{return}
        let changed=current != stage;jobs[i].stage=stage;jobs[i].progress=progress.map{min(1,max(0,$0))};jobs[i].updated=Date()
        if changed {await persist()}
    }
    private func bindLibrary(_ id:UUID,item:LibraryItem) async {guard let i=jobs.firstIndex(where:{$0.id==id}) else{return};jobs[i].libraryID=item.id;if jobs[i].accountEmail==nil {jobs[i].accountEmail=item.accountEmail};await persist()}
    private func checkCancellation(_ id:UUID) throws {if current(id)?.cancelRequested==true {throw AppFailure("canceled","Operation canceled.")}}
    private func run(_ id:UUID) async {
        var staged:URL?
        defer {if let staged {try? FileManager.default.removeItem(at:staged);try? FileManager.default.removeItem(at:URL(fileURLWithPath:staged.path+".tmp"))}}
        do {
            guard let job=current(id) else{return};try checkCancellation(id)
            await update(id,stage:.resolving)
            if let target=job.targetDeviceID {
                let targetApps=try await device.applications(on:target)
                if targetApps.contains(where:{$0.bundleID==job.app.bundleID && !$0.offloaded}) {await complete(id,.skipped,message:"The app is already installed on this device.");return}
            }
            var item:LibraryItem?
            if let libraryID=job.libraryID {item=await library.snapshot().first{$0.id==libraryID && !$0.missing};if item==nil {throw AppFailure("missingArchive","The selected archive is missing. Download or import it again.")}}
            if item==nil {item=await library.matching(job.app,accountID:job.accountID)}
            if item==nil {
                guard !job.app.testFlight,let storeID=job.app.storeItemID,storeID>0 else {throw AppFailure("unsupportedApp","App Store metadata is missing or this app was installed through TestFlight.")}
                guard let accountID=job.accountID else {await update(id,stage:.awaitingAccount,message:"Choose an Apple Account to download this application.",code:"accountRequired");return}
                let accounts=try await store.accounts()
                guard accounts.contains(where:{$0.id==accountID && $0.authenticated}) else {await update(id,stage:.awaitingAccount,message:"Sign in to the Apple Account used for this application.",code:"authenticationRequired");return}
                var requested=job.app
                do {requested=try await store.versionInfo(app:job.app,accountID:accountID,latest:false)} catch {
                    let failure=error as? AppFailure
                    if !["licenseRequired","authenticationRequired","accountRequired","sessionExpired","canceled"].contains(failure?.code ?? ""),let latest=try? await store.versionInfo(app:job.app,accountID:accountID,latest:true),((job.app.externalVersionID ?? "").isEmpty || !latest.sameBuild(as:job.app)) {
                        if let i=jobs.firstIndex(where:{$0.id==id}) {jobs[i].alternative=latest}
                        await update(id,stage:.awaitingVersionChoice,message:"The exact source version is unavailable. Review the available version before continuing.",code:"versionUnavailable");return
                    };throw error
                }
                guard requested.version==job.app.version || job.app.version.isEmpty else {
                    if let i=jobs.firstIndex(where:{$0.id==id}) {jobs[i].alternative=requested}
                    await update(id,stage:.awaitingVersionChoice,message:"Choose whether to use the available version.",code:"versionUnavailable");return
                }
                try checkCancellation(id)
                let output=await library.stagingURL();staged=output
                await update(id,stage:.downloading)
                try await store.download(app:requested,accountID:accountID,to:output){[weak self] fraction in Task{await self?.reportProgress(id,stage:.downloading,progress:fraction)}}
                try checkCancellation(id);await update(id,stage:.validating)
                let inspection=try await Task.detached(priority:.utility){try IPAInspector.inspect(output,expected:requested)}.value
                try checkCancellation(id)
                item=try await library.add(stagedURL:output,inspection:inspection,accountID:accountID,email:job.accountEmail)
                staged=nil
            }
            guard let item else {throw AppFailure("missingArchive","No validated archive is available.")}
            await bindLibrary(id,item:item);try checkCancellation(id)
            guard let target=job.targetDeviceID else {await complete(id,.succeeded,message:"Saved to the local library.");return}
            let devices=try await device.devices()
            guard let phone=devices.first(where:{$0.id==target}) else {throw AppFailure("deviceUnavailable","Reconnect the destination iPhone.")}
            if let minimum=item.app.minimumOS,!phone.iOS.isEmpty,phone.iOS.compare(minimum,options:.numeric) == .orderedAscending {throw AppFailure("incompatibleOS","The app requires a newer version of iOS.")}
            if !item.app.deviceFamilies.isEmpty,!item.app.deviceFamilies.contains(1) {throw AppFailure("incompatibleDevice","This archive does not support iPhone.")}
            if let free=phone.freeBytes,free<item.bytes*2 {throw AppFailure("noSpace","Not enough free storage on the destination iPhone.")}
            let url=try await library.url(for:item)
            await update(id,stage:.validating)
            let checked=try await Task.detached(priority:.utility){try IPAInspector.inspect(url,expected:item.app)}.value
            guard checked.sha256==item.sha256 else{throw AppFailure("archiveChanged","The saved IPA changed since it was added. Import or download a fresh copy.")}
            try checkCancellation(id)
            await update(id,stage:.uploading)
            let flag=cancellation ?? CancellationFlag()
            try await device.install(url,on:target,cancellation:flag){[weak self] stage,progress in Task{await self?.reportProgress(id,stage:stage,progress:progress)}}
            await update(id,stage:.verifying)
            let actual=try await device.applications(on:target)
            guard let found=actual.first(where:{$0.bundleID==item.app.bundleID && !$0.offloaded}),found.sameBuild(as:item.app) else {throw AppFailure("verificationFailed","The device did not confirm the requested app and version. Refresh before retrying.")}
            await complete(id,.succeeded,message:"Installed and verified. Open the app on the iPhone; its Apple Account or app login may still be required.")
        } catch {
            let failure=error as? AppFailure ?? AppFailure("operationFailed",error.localizedDescription)
            if failure.code=="canceled" {await complete(id,.canceled)}
            else if ["deviceUnavailable","deviceLocked","trustRequired"].contains(failure.code) {await update(id,stage:.awaitingDevice,message:failure.message,code:failure.code)}
            else if ["authenticationRequired","accountRequired","sessionExpired","licenseRequired"].contains(failure.code) {await update(id,stage:.awaitingAccount,message:failure.message,code:failure.code)}
            else {await complete(id,.failed,message:failure.message,code:failure.code)}
        }
    }
    private func complete(_ id:UUID,_ stage:JobStage,message:String?=nil,code:String?=nil) async {
        guard let i=jobs.firstIndex(where:{$0.id==id}) else{return};jobs[i].stage=stage;jobs[i].progress=nil;jobs[i].message=message;jobs[i].errorCode=code;jobs[i].updated=Date();history.append(ActivityEntry(job:jobs[i]));await persist()
    }
    private func persist() async {do{try await persistence.save(jobs:jobs,history:history,paused:paused);persistenceError=nil}catch{persistenceError=error.localizedDescription}}
}
