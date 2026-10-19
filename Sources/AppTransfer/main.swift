import AppKit
import SwiftUI
import AppTransferCore
import Darwin

@MainActor final class ApplicationDelegate:NSObject,NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification:Notification){NSApp.setActivationPolicy(.regular);NSApp.activate(ignoringOtherApps:true);WindowSnapshotCapture.scheduleIfRequested()}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
}

struct AppTransferApplication:App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @StateObject private var model=AppModel(isDemo:CommandLine.arguments.contains("--demo"))
    var body:some Scene {
        WindowGroup("iPhone App Transfer") {
            WorkspaceView(model:model)
                .onReceive(NotificationCenter.default.publisher(for:NSApplication.willTerminateNotification)){_ in model.shutdown()}
        }
        .defaultSize(width:1160,height:820)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing:.newItem){Button(model.prefs.t("Импортировать IPA…","Import IPA…")){model.importIPA()}.keyboardShortcut("o",modifiers:.command).disabled(model.isDemo)}
            CommandGroup(replacing:.appSettings){Button(model.prefs.t("Настройки…","Settings…")){model.showAccounts=false;model.showSettings.toggle()}.keyboardShortcut(",",modifiers:.command)}
            CommandGroup(after:.toolbar) {
                Button(model.prefs.t("Библиотека","Library")){withAnimation(.easeOut(duration:0.24)){model.prefs.libraryVisible.toggle()}}.keyboardShortcut("s",modifiers:.command)
                Button(model.prefs.t("Очередь","Queue")){withAnimation(.easeOut(duration:0.2)){model.prefs.queueVisible.toggle()}}.keyboardShortcut("j",modifiers:.command)
                Button(model.prefs.t("Обновить устройства","Refresh Devices")){model.refresh()}.keyboardShortcut("r",modifiers:.command)
            }
            CommandGroup(after:.pasteboard){Button(model.prefs.t("Удалить из библиотеки…","Delete from Library…")){model.requestDeleteSelection()}.keyboardShortcut(.delete,modifiers:.command).disabled(model.currentTab != "devices" || !model.prefs.libraryVisible || model.selectedLocation != "library" || model.selectedIDs.isEmpty)}
        }
    }
}

/// Captures only this app's NSView. Schedule from the application lifecycle so
/// replacing a SwiftUI background view cannot discard the pending capture.
@MainActor private enum WindowSnapshotCapture {
    static func scheduleIfRequested(){
        guard let index=CommandLine.arguments.firstIndex(of:"--snapshot"),CommandLine.arguments.indices.contains(index+1) else{return}
        let path=CommandLine.arguments[index+1]
        DispatchQueue.main.asyncAfter(deadline:.now()+3){capture(path:path,attempt:0)}
    }
    private static func capture(path:String,attempt:Int){
        let window=NSApp.mainWindow ?? NSApp.windows.first(where:{$0.isVisible && $0.canBecomeMain})
        guard let content=window?.contentView,content.bounds.width>0,content.bounds.height>0 else{
            if attempt<8 {DispatchQueue.main.asyncAfter(deadline:.now()+0.35){capture(path:path,attempt:attempt+1)}}
            else {finish(message:"Snapshot failed: application window unavailable.")}
            return
        }
        content.layoutSubtreeIfNeeded()
        guard let bitmap=content.bitmapImageRepForCachingDisplay(in:content.bounds) else{finish(message:"Snapshot failed: bitmap unavailable.");return}
        content.cacheDisplay(in:content.bounds,to:bitmap)
        guard let data=bitmap.representation(using:.png,properties:[:]) else{finish(message:"Snapshot failed: PNG encoding unavailable.");return}
        do{
            let url=URL(fileURLWithPath:path)
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try data.write(to:url,options:.atomic)
            finish(message:nil)
        }catch{finish(message:"Snapshot failed: could not write PNG.")}
    }
    private static func finish(message:String?){
        if let message{
            if let data=(message+"\n").data(using:.utf8){FileHandle.standardError.write(data)}
            exit(EXIT_FAILURE)
        }
        if CommandLine.arguments.contains("--quit-after-snapshot"){NSApp.terminate(nil)}
    }
}

/// Snapshot fixtures use an explicit native window instead of scene restoration.
/// This path is reachable only with both --demo and --snapshot.
@MainActor private final class DemoSnapshotHost {
    private static var retained:DemoSnapshotHost?
    private let application:NSApplication
    private let delegate:ApplicationDelegate
    private let model:AppModel
    private let window:NSWindow
    private init(){
        application=NSApplication.shared
        delegate=ApplicationDelegate()
        model=AppModel(isDemo:true)
        let width=Self.dimension("--snapshot-width",fallback:1160,minimum:760,maximum:1800)
        let height=Self.dimension("--snapshot-height",fallback:820,minimum:560,maximum:1200)
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        application.setActivationPolicy(.regular)
        application.delegate=delegate
        window.title="iPhone App Transfer"
        window.contentMinSize=NSSize(width:760,height:560)
        window.isReleasedWhenClosed=false
        window.contentView=NSHostingView(rootView:WorkspaceView(model:model))
        window.center()
    }
    static func run(){
        let host=DemoSnapshotHost()
        retained=host
        host.window.makeKeyAndOrderFront(nil)
        host.application.activate(ignoringOtherApps:true)
        host.application.run()
        retained=nil
    }
    private static func dimension(_ flag:String,fallback:CGFloat,minimum:CGFloat,maximum:CGFloat)->CGFloat{
        guard let index=CommandLine.arguments.firstIndex(of:flag),CommandLine.arguments.indices.contains(index+1),let value=Double(CommandLine.arguments[index+1]),value.isFinite else{return fallback}
        return min(maximum,max(minimum,CGFloat(value)))
    }
}

if CommandLine.arguments.contains("--diagnostics") {
    let semaphore=DispatchSemaphore(value:0)
    Task.detached {
        var output:[String:Any]=["mode":"read-only","architecture":"arm64","deviceWrites":false]
        do {let device=DeviceService();let phones=try await device.devices();var summaries:[[String:Any]]=[];for phone in phones{let apps=try await device.applications(on:phone.id);summaries.append(["model":phone.model,"iOS":phone.iOS,"state":phone.state,"apps":apps.count,"offloaded":apps.filter(\.offloaded).count,"storeMetadata":apps.filter{$0.storeItemID != nil}.count])};output["devices"]=summaries}catch{output["deviceError"]=(error as? AppFailure)?.code ?? "error"}
        do {let store=AppStoreService();let hello=try await store.hello();let accounts=try await store.accounts();output["helper"]=hello;output["accountCount"]=accounts.count;await store.shutdown()}catch{output["helperError"]=(error as? AppFailure)?.code ?? "error"}
        if let data=try? JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]),let string=String(data:data,encoding:.utf8){print(string)}
        semaphore.signal()
    }
    semaphore.wait()
}else if CommandLine.arguments.contains("--demo") && CommandLine.arguments.contains("--snapshot"){
    MainActor.assumeIsolated{DemoSnapshotHost.run()}
}else{
    AppTransferApplication.main()
}
