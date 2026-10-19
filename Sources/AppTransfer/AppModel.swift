import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import AppTransferCore

struct AuthUIState {
    var phase="idle"
    var accountID:String?
    var email=""
    var message:String?
}

struct QueueFeedback: Identifiable {
    let id = UUID()
    let jobIDs: Set<UUID>
    let focusJobID: UUID
    let message: String
}

@MainActor final class AppModel:ObservableObject {
    @Published var devices:[Phone]=[]
    @Published var library:[AppTransferCore.LibraryItem]=[]
    @Published var jobs:[TransferJob]=[]
    @Published var activity:[ActivityEntry]=[]
    @Published var accounts:[AppleAccount]=[]
    @Published var accountsLoading=true
    @Published var selectedLocation:String?
    @Published var selectedIDs:Set<String>=[]
    @Published var currentTab="devices"
    @Published var showSettings=false
    @Published var showAccounts=false
    @Published var pendingDeletion:[AppTransferCore.LibraryItem]=[]
    @Published var globalError:String?
    @Published var statusMessage:String?
    @Published var isRefreshing=false
    @Published var queuePaused=false
    @Published var queueFeedback:QueueFeedback?
    @Published var selectedAccountID:String?
    @Published var auth=AuthUIState()
    let prefs:Preferences
    let isDemo:Bool
    private let device:DeviceService?
    private let store:AppStoreService?
    private let libraryStore:LibraryStore?
    private let coordinator:TransferCoordinator?
    private let libraryRoot:URL
    private var pollTask:Task<Void,Never>?
    private var preferenceSink:AnyCancellable?
    private var imageCache:[String:NSImage]=[:]
    private var imageRequests:Set<String>=[]
    private var anchorID:String?
    private var lastHistoryCount=0
    private var refreshTick=0
    private var toastTask:Task<Void,Never>?
    private var queueFeedbackTask:Task<Void,Never>?
    private var authGeneration=UUID()
    init(isDemo:Bool=false){
        self.isDemo=isDemo
        let defaults=UserDefaults(suiteName:isDemo ? "com.apptransfer.AppTransfer.demo":"com.apptransfer.AppTransfer") ?? .standard
        prefs=Preferences(defaults:defaults)
        libraryRoot=AppPaths.root.appendingPathComponent("Library")
        if isDemo {device=nil;store=nil;libraryStore=nil;coordinator=nil}
        else {
            let device=DeviceService(),store=AppStoreService();self.device=device;self.store=store
            do {let library=try LibraryStore(root:libraryRoot),operations=try OperationStore();libraryStore=library;coordinator=TransferCoordinator(device:device,store:store,library:library,persistence:operations)}catch{libraryStore=nil;coordinator=nil;globalError=error.localizedDescription}
        }
        preferenceSink=prefs.objectWillChange.sink{[weak self] _ in self?.objectWillChange.send()}
        if let index=CommandLine.arguments.firstIndex(of:"--language"),CommandLine.arguments.indices.contains(index+1){prefs.language=CommandLine.arguments[index+1]}
        if let index=CommandLine.arguments.firstIndex(of:"--theme"),CommandLine.arguments.indices.contains(index+1){prefs.theme=CommandLine.arguments[index+1]}
        if isDemo {loadDemo();return}
        device?.onChange{[weak self] in Task{@MainActor in self?.refresh()}}
        Task{[weak self] in
            guard let self else{return}
            do {try await self.coordinator?.start()}catch{self.present(error)}
            if let coordinator=self.coordinator {self.applyQueueSnapshot(await coordinator.snapshot())}
            if let libraryStore=self.libraryStore {self.library=await libraryStore.snapshot()}
            self.refresh();self.startPolling()
            await self.reloadAccounts()
        }
    }
    func refresh(){
        guard !isDemo,!isRefreshing,let device else{return}
        isRefreshing=true
        Task{[weak self] in
            guard let self else{return}
            do {
                var phones=try await device.devices()
                for i in phones.indices {
                    do {phones[i].apps=try await device.applications(on:phones[i].id)}
                    catch {phones[i].state=(error as? AppFailure)?.code ?? "deviceError";phones[i].apps=self.devices.first{$0.id==phones[i].id}?.apps ?? []}
                }
                self.devices=phones
                if let location=self.selectedLocation,location != "library",!phones.contains(where:{$0.id==location}){self.selectedIDs=[];self.selectedLocation=nil}
            }catch{self.present(error)}
            self.isRefreshing=false
        }
    }
    private func startPolling(){
        pollTask=Task{[weak self] in
            while !Task.isCancelled {
                guard let self else{return}
                if let coordinator=self.coordinator {
                    self.applyQueueSnapshot(await coordinator.snapshot())
                }
                if let library=self.libraryStore {self.library=await library.snapshot()}
                self.refreshTick+=1;if self.refreshTick % 40==0 {self.refresh()}
                try? await Task.sleep(nanoseconds:500_000_000)
            }
        }
    }
    func select(id:String,location:String,extend:Bool,range:Bool=false,orderedIDs:[String]?=nil){
        let previousLocation=selectedLocation
        if range,previousLocation==location,let anchorID {
            let ordered=orderedIDs ?? (location=="library" ? library.map{$0.id.uuidString}:devices.first{$0.id==location}?.apps.map(\.bundleID) ?? [])
            if let a=ordered.firstIndex(of:anchorID),let b=ordered.firstIndex(of:id){selectedIDs.formUnion(ordered[min(a,b)...max(a,b)])}
            else{selectedIDs=[id];self.anchorID=id}
        }else if extend,previousLocation==location {if selectedIDs.contains(id){selectedIDs.remove(id)}else{selectedIDs.insert(id)};anchorID=id}
        else {selectedIDs=[id];anchorID=id}
        selectedLocation=location
    }
    func dropPayload(for id:String,location:String)->String {
        if selectedLocation != location || !selectedIDs.contains(id){select(id:id,location:location,extend:false)}
        if location=="library" {return DropPayload(sourceDeviceID:nil,sourceName:prefs.t("Библиотека","Library"),libraryIDs:selectedIDs.compactMap(UUID.init(uuidString:))).encoded}
        return DropPayload(sourceDeviceID:location,sourceName:devices.first{$0.id==location}?.name ?? "iPhone",bundleIDs:Array(selectedIDs)).encoded
    }
    func transferSelection(to target:String?){guard let selectedLocation,let id=selectedIDs.first else{return};handleDrop(dropPayload(for:id,location:selectedLocation),to:target)}
    func handleDrop(_ text:String,to target:String?){
        guard !isDemo else {notify(prefs.t("Демонстрационный режим: операции с телефонами выключены.","Demo mode: device operations are disabled."));return}
        guard let payload=DropPayload.decode(text),let coordinator else{return}
        if payload.sourceDeviceID==target && target != nil {return}
        if target==nil && !payload.libraryIDs.isEmpty {return}
        let targetName=target.flatMap{id in devices.first{$0.id==id}?.name} ?? prefs.t("Библиотека","Library")
        var requests:[TransferJob]=[]
        if !payload.libraryIDs.isEmpty {
            for item in library.filter({payload.libraryIDs.contains($0.id)}) {
                requests.append(TransferJob(app:item.app,sourceName:prefs.t("Библиотека","Library"),targetDeviceID:target,targetName:targetName,accountID:item.accountID,accountEmail:item.accountEmail,libraryID:item.id,archiveAccounts:item.archiveAccounts))
            }
        }else if let source=payload.sourceDeviceID,let phone=devices.first(where:{$0.id==source}) {
            for app in phone.apps.filter({payload.bundleIDs.contains($0.bundleID)}) {
                let selection=accountSelection(for:app)
                requests.append(TransferJob(app:app,sourceDeviceID:source,sourceName:phone.name,targetDeviceID:target,targetName:targetName,accountID:selection.account?.id,accountEmail:selection.account?.email,accountSelectionReason:selection.reason))
            }
        }
        guard !requests.isEmpty else{return}
        Task {
            var inserted:[UUID]=[],existing:[UUID]=[]
            for job in requests {
                let outcome=await coordinator.enqueue(job)
                if outcome.inserted {inserted.append(outcome.jobID)} else {existing.append(outcome.jobID)}
            }
            applyQueueSnapshot(await coordinator.snapshot())
            if let focus=inserted.last {
                let message=inserted.count==1 ? prefs.t("Добавлено: ","Added: ")+(jobs.first{$0.id==focus}?.app.name ?? "") : prefs.t("Добавлено задач: ","Tasks added: ")+String(inserted.count)
                showQueueFeedback(ids:Set(inserted),focus:focus,message:message)
            } else if let focus=existing.last {
                showQueueFeedback(ids:Set(existing),focus:focus,message:prefs.t("Уже в очереди: ","Already queued: ")+(jobs.first{$0.id==focus}?.app.name ?? ""))
            }
        }
        currentTab="devices"
    }
    func accountSelection(for app:AppDescriptor)->AccountSelection {
        AccountResolver.resolve(for:app,accounts:accounts,defaultAccountID:selectedAccountID)
    }
    /// Preview only; the coordinator rechecks and validates the file before use.
    func previewArchive(for app:AppDescriptor)->AppTransferCore.LibraryItem? {
        let accountID=accountSelection(for:app).account?.id
        return library.first{!$0.missing && $0.app.sameBuild(as:app) && $0.accountID==accountID}
    }
    func requestDeleteSelection(){guard currentTab=="devices",prefs.libraryVisible,selectedLocation=="library" else{return};pendingDeletion=library.filter{selectedIDs.contains($0.id.uuidString)}}
    func confirmDelete(){
        let ids=Set(pendingDeletion.map(\.id));pendingDeletion=[]
        guard !isDemo,let coordinator,!ids.isEmpty else{if isDemo{notify(prefs.t("Удаление доступно в рабочем режиме.","Deletion is available in live mode."))};return}
        Task{do{_ = try await coordinator.removeLibraryItems(ids);selectedIDs.subtract(ids.map(\.uuidString));if let libraryStore{library=await libraryStore.snapshot()};notify(prefs.t("IPA перемещены в Корзину. Приложения на телефонах сохранены.","IPA files moved to Trash. Installed apps remain on devices."))}catch{present(error)}}
    }
    func importIPA(){
        guard !isDemo,let libraryStore else{return};let panel=NSOpenPanel();panel.allowedContentTypes=[UTType(filenameExtension:"ipa") ?? .data];panel.allowsMultipleSelection=true;panel.canChooseDirectories=false
        showSettings=false;showAccounts=false
        guard panel.runModal() == .OK else{return};let urls=panel.urls
        Task{var imported=0;for url in urls{do{_ = try await libraryStore.importIPA(url);imported+=1}catch{present(error)}};library=await libraryStore.snapshot();if imported>0{notify(prefs.t("Импортировано IPA: ","Imported IPA files: ")+String(imported))}}
    }
    func cancelJob(_ id:UUID){guard !isDemo else{return};Task{await coordinator?.cancel(id)}}
    func retryJob(_ id:UUID){guard !isDemo,let coordinator else{return};Task{if await coordinator.retry(id){applyQueueSnapshot(await coordinator.snapshot());showQueueFeedback(ids:[id],focus:id,message:prefs.t("Повторная попытка: ","Retry queued: ")+(jobs.first{$0.id==id}?.app.name ?? ""))}}}
    func toggleQueuePaused(){guard !isDemo else{return};Task{await coordinator?.setPaused(!queuePaused)}}
    func selectAccountForJob(jobID:UUID,accountID:String){guard !isDemo,let account=accounts.first(where:{$0.id==accountID && $0.authenticated}) else{return};Task{await coordinator?.assignAccount(jobID,account:account)}}
    func acceptAlternative(_ id:UUID){guard !isDemo else{return};Task{await coordinator?.acceptAlternative(id)}}
    func dismissError(){globalError=nil}
    var displayedJobs:[TransferJob]{QueuePresentation.newestFirst(jobs)}
    private func applyQueueSnapshot(_ snapshot:QueueSnapshot){
        jobs=snapshot.jobs;activity=snapshot.history;queuePaused=snapshot.paused
        if let error=snapshot.persistenceError,globalError==nil {globalError=prefs.t("Не удалось сохранить очередь: ","Could not save the queue: ")+error}
        if snapshot.history.count != lastHistoryCount {lastHistoryCount=snapshot.history.count;refresh()}
    }
    private func showQueueFeedback(ids:Set<UUID>,focus:UUID,message:String){
        let feedback=QueueFeedback(jobIDs:ids,focusJobID:focus,message:message)
        queueFeedback=feedback;queueFeedbackTask?.cancel()
        queueFeedbackTask=Task{try? await Task.sleep(nanoseconds:4_000_000_000);if !Task.isCancelled,queueFeedback?.id==feedback.id{queueFeedback=nil}}
    }
    func icon(for app:AppDescriptor,on deviceID:String?)->NSImage? {
        guard let deviceID else{return nil};let key=deviceID+"/"+app.bundleID
        if let cached=imageCache[key]{return cached}
        guard !isDemo,!imageRequests.contains(key),let device else{return nil};imageRequests.insert(key)
        Task{if let bytes=try? await device.icon(bundleID:app.bundleID,on:deviceID),let image=NSImage(data:bytes){imageCache[key]=image;objectWillChange.send()}}
        return nil
    }
    func libraryIcon(_ item:AppTransferCore.LibraryItem)->NSImage? {
        let key="library/"+item.id.uuidString;if let cached=imageCache[key]{return cached}
        guard !isDemo,let image=NSImage(contentsOf:libraryRoot.appendingPathComponent("Icons/\(item.id.uuidString).png")) else{return nil};imageCache[key]=image;return image
    }
    private func reloadAccounts() async {
        guard let store else{accountsLoading=false;return}
        accountsLoading=true
        defer{accountsLoading=false}
        do{accounts=try await store.accounts();if let selectedAccountID,!accounts.contains(where:{$0.id==selectedAccountID}){self.selectedAccountID=nil};if accounts.count==1{selectedAccountID=accounts[0].id}}catch{present(error)}
    }
    func beginLogin(email:String,password:String){
        guard !isDemo,let store,!email.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,!password.isEmpty else{return}
        let email=email.trimmingCharacters(in:.whitespacesAndNewlines)
        let generation=UUID();authGeneration=generation
        let accountID=accounts.first{$0.email.caseInsensitiveCompare(email) == .orderedSame}?.id ?? UUID().uuidString.lowercased()
        auth=AuthUIState(phase:"preparing",accountID:accountID,email:email,message:nil)
        let existing=auth.accountID
        Task{[weak self] in guard let self else{return};do{
            let account=try await store.login(email:email,password:password,accountID:existing){[weak self] kind,payload in
                let id=payload["accountId"] as? String
                Task{@MainActor in guard let self,self.authGeneration==generation else{return};if let id{self.auth.accountID=id};if kind=="auth.codeRequired"{self.auth.phase="code";self.auth.message=(payload["invalidPreviousCode"] as? Bool)==true ? self.prefs.t("Код не подошёл. Введите новый код.","That code was not accepted. Enter a new code."):nil}}
            }
            guard self.authGeneration==generation else{return}
            self.auth=AuthUIState(phase:"success",accountID:account.id,email:account.email,message:nil);await self.reloadAccounts();self.selectedAccountID=account.id
            self.notify(self.prefs.t("Вход выполнен.","Signed in."))
        }catch{if self.authGeneration==generation,self.auth.phase != "idle"{self.auth.phase="failed";self.auth.message=self.localized(error)}}}
    }
    func submitCode(_ code:String){guard !isDemo,auth.phase=="code",let store,let id=auth.accountID else{return};let generation=authGeneration;auth.message=nil;auth.phase="verifyingCode";Task{do{try await store.submitCode(accountID:id,code:code)}catch{if authGeneration==generation {auth.phase="code";auth.message=localized(error)}}}}
    func cancelLogin(){let id=auth.accountID;authGeneration=UUID();auth=AuthUIState();if let id{Task{await store?.cancelLogin(accountID:id)}}}
    func removeAccount(_ account:AppleAccount){guard !isDemo,let store else{return};Task{do{try await store.removeAccount(account.id);await reloadAccounts()}catch{present(error)}}}
    private func localized(_ error:Error)->String {let failure=error as? AppFailure;return prefs.failureMessage(failure?.code,fallback:error.localizedDescription)}
    private func present(_ error:Error){globalError=localized(error)}
    private func notify(_ message:String){statusMessage=message;toastTask?.cancel();toastTask=Task{try? await Task.sleep(nanoseconds:4_000_000_000);if !Task.isCancelled{statusMessage=nil}}}
    func shutdown(){pollTask?.cancel();queueFeedbackTask?.cancel();if let store{Task{await store.shutdown()}}}
    private func loadDemo(){
        accountsLoading=false
        let longEmail="download.account.with.a.long.address@example.com"
        func app(_ bundle:String,_ name:String,_ version:String,_ owner:String?="david@example.com")->AppDescriptor{AppDescriptor(bundleID:bundle,name:name,version:version,build:"1",storeItemID:1,externalVersionID:"1",ownerEmail:owner)}
        let avito=app("example.avito","Авито","200.5","angelina@example.com"),mail=app("example.mail","Mail App","15.92.0",longEmail),craft=app("example.craftersy","Craftersy","5.1","previous.owner@example.com"),yplaces=app("example.yplaces","YPLACES","1.30.1"),telegram=app("example.telegram","Telegram","12.0"),advance=app("example.advance","Advance","1.2"),au=app("example.au","AU","222.1"),online=app("example.online","Online","16.0.0"),whatsapp=app("example.whatsapp","WhatsApp","25.28")
        devices=[Phone(id:"demo-14",name:"Ангелина",model:"iPhone 14 Pro Max",iOS:"27.0.1",freeBytes:64_000_000_000,apps:[avito,app("example.tbank","Т-Банк","6.13.6"),yplaces,telegram,whatsapp,app("example.youtube","YouTube","20.40"),app("example.spotify","Spotify","9.0")]),Phone(id:"demo-16",name:"Давид",model:"iPhone 16 Pro Max",iOS:"18.5",freeBytes:128_000_000_000,apps:[craft,au,online,advance,mail,telegram]),Phone(id:"demo-17",name:"Ангелина",model:"iPhone 17 Pro Max",iOS:"27.0.1",freeBytes:204_000_000_000,apps:[avito,mail,telegram,whatsapp])]
        if let index=CommandLine.arguments.firstIndex(of:"--demo-device-count"),CommandLine.arguments.indices.contains(index+1),let count=Int(CommandLine.arguments[index+1]),count>devices.count,count<=20{
            let examples=devices
            for number in (devices.count+1)...count{
                let example=examples[(number-1)%examples.count]
                devices.append(Phone(id:"demo-extra-\(number)",name:prefs.t("Демо iPhone ","Demo iPhone ")+String(number),model:example.model,iOS:example.iOS,freeBytes:example.freeBytes,apps:example.apps))
            }
        }
        let imported=app("example.imported","Imported IPA","1.0",nil)
        var downloadedCraft=craft;downloadedCraft.ownerEmail=longEmail
        library=[
            AppTransferCore.LibraryItem(app:avito,accountID:"demo-account2",accountEmail:"angelina@example.com",relativePath:"demo.ipa",bytes:174_000_000,sha256:"demo",hasSinf:true,origin:.appStore),
            AppTransferCore.LibraryItem(app:mail,accountID:"demo-download",accountEmail:longEmail,relativePath:"demo2.ipa",bytes:112_000_000,sha256:"demo",hasSinf:true,origin:.appStore),
            AppTransferCore.LibraryItem(app:downloadedCraft,accountID:"demo-download",accountEmail:longEmail,relativePath:"demo3.ipa",bytes:498_000_000,sha256:"demo",hasSinf:true,origin:.appStore),
            AppTransferCore.LibraryItem(app:imported,accountID:nil,accountEmail:nil,relativePath:"demo-import.ipa",bytes:24_000_000,sha256:"demo",hasSinf:false,origin:.imported),
            AppTransferCore.LibraryItem(app:telegram,accountID:nil,accountEmail:"david@example.com",relativePath:"demo-import-known.ipa",bytes:40_000_000,sha256:"demo",hasSinf:true,origin:.imported),
            AppTransferCore.LibraryItem(app:advance,accountID:"demo-download",accountEmail:longEmail,relativePath:"demo-conflict.ipa",bytes:20_000_000,sha256:"demo",hasSinf:true,origin:.appStore)
        ]
        accounts=[AppleAccount(id:"demo-account",email:"david@example.com",storefront:"RU",authenticated:true),AppleAccount(id:"demo-account2",email:"angelina@example.com",storefront:"US",authenticated:true),AppleAccount(id:"demo-download",email:longEmail,storefront:"143441",authenticated:true),AppleAccount(id:"demo-expired",email:"expired.account@example.com",authenticated:false)]
        selectedAccountID="demo-download"
        var first=TransferJob(app:craft,sourceDeviceID:"demo-16",sourceName:"iPhone 16",targetDeviceID:"demo-17",targetName:"iPhone 17",accountID:"demo-download",accountEmail:longEmail,accountSelectionReason:.defaultAccount);first.stage = .downloading;first.progress=0.42
        var completed=TransferJob(app:craft,sourceDeviceID:"demo-16",sourceName:"iPhone 16",targetDeviceID:"demo-17",targetName:"iPhone 17",accountID:"demo-download",accountEmail:longEmail,libraryID:library[2].id,accountSelectionReason:.explicit,archiveAccounts:library[2].archiveAccounts);completed.stage = .succeeded
        var importedJob=TransferJob(app:imported,sourceName:prefs.t("Библиотека","Library"),targetDeviceID:"demo-17",targetName:"iPhone 17",libraryID:library[3].id,archiveAccounts:library[3].archiveAccounts);importedJob.stage = .queued
        var waiting=TransferJob(app:online,sourceDeviceID:"demo-16",sourceName:"iPhone 16",targetName:prefs.t("Библиотека","Library"),accountID:"demo-expired",accountEmail:"expired.account@example.com",accountSelectionReason:.explicit);waiting.stage = .awaitingAccount;waiting.errorCode="sessionExpired"
        jobs=[completed,importedJob,waiting,first];queuePaused=true
        activity=[ActivityEntry(job:completed)]
        selectedLocation="demo-16";selectedIDs=[craft.bundleID]
    }
}
