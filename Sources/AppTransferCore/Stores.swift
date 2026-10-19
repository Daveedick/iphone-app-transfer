import Foundation

public enum AppPaths {
    public static var root: URL {
        if let override=ProcessInfo.processInfo.environment["APPTRANSFER_DATA_DIR"] {return URL(fileURLWithPath:override,isDirectory:true)}
        return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("AppTransfer",isDirectory:true)
    }
    public static func prepare(_ url:URL) throws {try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:url.path)}
}

public enum AtomicJSON {
    public static func load<T:Decodable>(_ type:T.Type,from url:URL) throws -> T {try JSONDecoder().decode(type,from:Data(contentsOf:url))}
    public static func save<T:Encodable>(_ value:T,to url:URL) throws {let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];let data=try encoder.encode(value);try data.write(to:url,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)}
}

public actor LibraryStore {
    private struct Manifest:Codable {var schema=1;var items:[LibraryItem]}
    public let root:URL
    private let manifestURL:URL
    private var items:[LibraryItem]=[]
    public init(root:URL=AppPaths.root.appendingPathComponent("Library")) throws {self.root=root;manifestURL=root.appendingPathComponent("manifest.json");try AppPaths.prepare(root);try AppPaths.prepare(root.appendingPathComponent("Staging"));try AppPaths.prepare(root.appendingPathComponent("Icons"));if FileManager.default.fileExists(atPath:manifestURL.path) {let saved=try AtomicJSON.load(Manifest.self,from:manifestURL);guard saved.schema==1 else {throw AppFailure("schema","Unsupported library schema.")};items=saved.items;for i in items.indices {items[i].missing = !FileManager.default.fileExists(atPath:root.appendingPathComponent(items[i].relativePath).path)}}}
    public func snapshot() -> [LibraryItem] {
        // A file can disappear while the app remains open (Finder, an external disk,
        // or a previously interrupted deletion). Never keep advertising it as ready.
        for i in items.indices {
            items[i].missing = (try? url(for:items[i])).map { !FileManager.default.fileExists(atPath:$0.path) } ?? true
        }
        return items.sorted{$0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending}
    }
    public func stagingURL() -> URL {root.appendingPathComponent("Staging/\(UUID().uuidString).partial")}
    public func url(for item:LibraryItem) throws -> URL {
        let url=root.appendingPathComponent(item.relativePath).standardizedFileURL
        guard url.deletingLastPathComponent()==root.standardizedFileURL, url.pathExtension=="ipa", url.resolvingSymlinksInPath().deletingLastPathComponent()==root.resolvingSymlinksInPath() else {throw AppFailure("unsafePath","Library path is outside managed storage.")}
        return url
    }
    public func iconURL(for item:LibraryItem) -> URL {root.appendingPathComponent("Icons/\(item.id.uuidString).png")}
    public func matching(_ app:AppDescriptor,accountID:String?) -> LibraryItem? {snapshot().first{!$0.missing && $0.app.sameBuild(as:app) && $0.accountID==accountID}}
    public func add(stagedURL:URL,inspection:IPAInspection,accountID:String?,email:String?,origin:ArchiveOrigin = .appStore) throws -> LibraryItem {
        if let existing=items.first(where:{$0.sha256==inspection.sha256 && $0.accountID==accountID && !$0.missing}) {if stagedURL.standardizedFileURL.path.hasPrefix(root.appendingPathComponent("Staging").path+"/") {try? FileManager.default.removeItem(at:stagedURL)};return existing}
        let id=UUID(),relative="\(id.uuidString).ipa",destination=root.appendingPathComponent(relative)
        try FileManager.default.moveItem(at:stagedURL,to:destination)
        let item=LibraryItem(id:id,app:inspection.app,accountID:accountID,accountEmail:email,relativePath:relative,bytes:inspection.bytes,sha256:inspection.sha256,hasSinf:inspection.hasSinf,origin:origin)
        if let icon=inspection.icon {try? icon.write(to:iconURL(for:item),options:.atomic)}
        items.append(item)
        do {try persist()} catch {items.removeAll{$0.id==id};try? FileManager.default.moveItem(at:destination,to:stagedURL);throw error}
        return item
    }
    public func importIPA(_ source:URL) async throws -> LibraryItem {let staged=stagingURL();do {let inspection=try await Task.detached(priority:.utility){try FileManager.default.copyItem(at:source,to:staged);return try IPAInspector.inspect(staged)}.value;return try add(stagedURL:staged,inspection:inspection,accountID:nil,email:nil,origin:.imported)}catch{try? FileManager.default.removeItem(at:staged);throw error}}
    public func delete(ids:Set<UUID>,busy:Set<UUID>,recycle:((URL)throws->Void)?=nil) throws -> [LibraryItem] {
        guard ids.isDisjoint(with:busy) else {throw AppFailure("libraryBusy","An archive is used by the queue. Cancel its waiting tasks or wait for completion.")}
        var removed:[LibraryItem]=[]
        for item in items.filter({ids.contains($0.id)}) {
            let file=try url(for:item)
            if FileManager.default.fileExists(atPath:file.path) {
                do {if let recycle {try recycle(file)} else {try FileManager.default.trashItem(at:file,resultingItemURL:nil)}}catch{try persist();throw error}
            }
            items.removeAll{$0.id==item.id};removed.append(item);try? FileManager.default.removeItem(at:iconURL(for:item));try persist()
        }
        return removed
    }
    private func persist() throws {try AtomicJSON.save(Manifest(items:items),to:manifestURL)}
}

public actor OperationStore {
    private struct State:Codable {var schema=1;var jobs:[TransferJob];var history:[ActivityEntry];var paused:Bool?}
    private let path:URL
    public init(root:URL=AppPaths.root) throws {try AppPaths.prepare(root);path=root.appendingPathComponent("operations.json")}
    public func load() throws -> (jobs:[TransferJob],history:[ActivityEntry],paused:Bool) {guard FileManager.default.fileExists(atPath:path.path) else {return([],[],false)};let state=try AtomicJSON.load(State.self,from:path);guard state.schema==1 else {throw AppFailure("schema","Unsupported operation history schema.")};return(state.jobs,state.history,state.paused ?? false)}
    public func save(jobs:[TransferJob],history:[ActivityEntry],paused:Bool=false) throws {try AtomicJSON.save(State(jobs:jobs,history:Array(history.suffix(10000)),paused:paused),to:path)}
}
