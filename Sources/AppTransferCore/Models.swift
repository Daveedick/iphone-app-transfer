import Foundation

public struct AppDescriptor: Codable, Hashable, Identifiable, Sendable {
    public var id: String { bundleID }
    public var bundleID: String
    public var name: String
    public var version: String
    public var build: String
    public var storeItemID: Int64?
    public var externalVersionID: String?
    public var ownerEmail: String?
    public var offloaded: Bool
    public var testFlight: Bool
    public var minimumOS: String?
    public var deviceFamilies: [Int]
    public init(bundleID: String, name: String, version: String, build: String = "", storeItemID: Int64? = nil, externalVersionID: String? = nil, ownerEmail: String? = nil, offloaded: Bool = false, testFlight: Bool = false, minimumOS: String? = nil, deviceFamilies: [Int] = []) {
        self.bundleID=bundleID; self.name=name; self.version=version; self.build=build; self.storeItemID=storeItemID; self.externalVersionID=externalVersionID; self.ownerEmail=ownerEmail; self.offloaded=offloaded; self.testFlight=testFlight; self.minimumOS=minimumOS; self.deviceFamilies=deviceFamilies
    }
    public func sameBuild(as other: AppDescriptor) -> Bool {
        guard bundleID == other.bundleID, version == other.version else { return false }
        if let a=externalVersionID, let b=other.externalVersionID { return a == b }
        return build.isEmpty || other.build.isEmpty || build == other.build
    }
}

public struct Phone: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var model: String
    public var iOS: String
    public var freeBytes: Int64?
    public var state: String
    public var apps: [AppDescriptor]
    public init(id: String, name: String, model: String, iOS: String, freeBytes: Int64? = nil, state: String = "connected", apps: [AppDescriptor] = []) { self.id=id; self.name=name; self.model=model; self.iOS=iOS; self.freeBytes=freeBytes; self.state=state; self.apps=apps }
    public var shortID: String { String(id.suffix(4)) }
}

public struct AppleAccount: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var email: String
    public var name: String?
    public var storefront: String?
    public var authenticated: Bool
    public init(id: String, email: String, name: String? = nil, storefront: String? = nil, authenticated: Bool = false) { self.id=id; self.email=email; self.name=name; self.storefront=storefront; self.authenticated=authenticated }
}

public struct LibraryItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var app: AppDescriptor
    public var accountID: String?
    public var accountEmail: String?
    public var relativePath: String
    public var bytes: Int64
    public var sha256: String
    public var created: Date
    public var hasSinf: Bool
    public var missing: Bool
    public var origin: ArchiveOrigin?
    public var archiveAccounts: ArchiveAccountContext {
        let source = origin ?? (accountID == nil ? .unknown : .appStore)
        // Older imports stored the metadata owner in accountEmail. A nonempty
        // email without a download account ID is not download provenance.
        let metadataOwner = app.ownerEmail ?? (accountID == nil ? accountEmail : nil)
        return ArchiveAccountContext(origin: source,
            downloadAccountID: source == .appStore ? accountID : nil,
            downloadAccountEmail: source == .appStore && accountID != nil ? accountEmail : nil,
            metadataOwnerEmail: metadataOwner)
    }
    public init(id: UUID = UUID(), app: AppDescriptor, accountID: String?, accountEmail: String?, relativePath: String, bytes: Int64, sha256: String, created: Date = Date(), hasSinf: Bool, missing: Bool = false, origin: ArchiveOrigin? = nil) { self.id=id; self.app=app; self.accountID=accountID; self.accountEmail=accountEmail; self.relativePath=relativePath; self.bytes=bytes; self.sha256=sha256; self.created=created; self.hasSinf=hasSinf; self.missing=missing; self.origin=origin }
}

public enum JobStage: String, Codable, Sendable {
    case queued, resolving, awaitingAccount, awaitingDevice, awaitingVersionChoice, downloading, validating, uploading, installing, verifying, succeeded, skipped, failed, canceled, interrupted
    public var terminal: Bool { [.succeeded,.skipped,.failed,.canceled].contains(self) }
    public var waiting: Bool { [.awaitingAccount,.awaitingDevice,.awaitingVersionChoice,.interrupted].contains(self) }
    public var deviceMutation: Bool { [.uploading,.installing,.verifying].contains(self) }
}

public struct TransferJob: Codable, Identifiable, Sendable {
    public var id: UUID
    public var app: AppDescriptor
    public var sourceDeviceID: String?
    public var sourceName: String
    public var targetDeviceID: String?
    public var targetName: String
    public var accountID: String?
    public var accountEmail: String?
    public var libraryID: UUID?
    public var stage: JobStage
    public var progress: Double?
    public var message: String?
    public var errorCode: String?
    public var created: Date
    public var updated: Date
    /// Queue presentation recency changes only for an accepted enqueue or retry.
    /// Older saved jobs omit this field and continue to use their creation date.
    public var lastQueuedAt: Date?
    public var queuePresentationDate: Date { lastQueuedAt ?? created }
    public var cancelRequested: Bool
    public var alternative: AppDescriptor?
    public var accountSelectionReason: AccountSelectionReason?
    public var archiveAccounts: ArchiveAccountContext?
    public init(app: AppDescriptor, sourceDeviceID: String? = nil, sourceName: String, targetDeviceID: String? = nil, targetName: String, accountID: String? = nil, accountEmail: String? = nil, libraryID: UUID? = nil, accountSelectionReason: AccountSelectionReason? = nil, archiveAccounts: ArchiveAccountContext? = nil) { id=UUID(); self.app=app; self.sourceDeviceID=sourceDeviceID; self.sourceName=sourceName; self.targetDeviceID=targetDeviceID; self.targetName=targetName; self.accountID=accountID; self.accountEmail=accountEmail; self.libraryID=libraryID; stage = .queued; progress=nil; message=nil; errorCode=nil; created=Date(); updated=Date(); lastQueuedAt=nil; cancelRequested=false; alternative=nil; self.accountSelectionReason=accountSelectionReason; self.archiveAccounts=archiveAccounts }
}

public struct ActivityEntry: Codable, Identifiable, Sendable {
    public var id: UUID
    public var jobID: UUID?
    public var appName: String
    public var version: String
    public var source: String
    public var target: String
    public var accountEmail: String?
    public var stage: JobStage
    public var message: String?
    public var date: Date
    public var archiveAccounts: ArchiveAccountContext?
    public var installedOnDevice: Bool?
    public init(job: TransferJob) { id=UUID(); jobID=job.id; appName=job.app.name; version=job.app.version; source=job.sourceName; target=job.targetName; accountEmail=job.accountEmail; stage=job.stage; message=job.message; date=Date(); archiveAccounts=job.archiveAccounts; installedOnDevice=job.stage == .succeeded && job.targetDeviceID != nil }
    public init(appName: String, version: String, source: String, target: String, message: String) { id=UUID(); jobID=nil; self.appName=appName; self.version=version; self.source=source; self.target=target; accountEmail=nil; stage = .succeeded; self.message=message; date=Date(); archiveAccounts=nil; installedOnDevice=false }
}

public struct DropPayload: Codable, Sendable {
    public var sourceDeviceID: String?
    public var sourceName: String
    public var bundleIDs: [String]
    public var libraryIDs: [UUID]
    public init(sourceDeviceID: String?, sourceName: String, bundleIDs: [String] = [], libraryIDs: [UUID] = []) { self.sourceDeviceID=sourceDeviceID; self.sourceName=sourceName; self.bundleIDs=bundleIDs; self.libraryIDs=libraryIDs }
    public var encoded: String { (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? "" }
    public static func decode(_ value: String) -> DropPayload? { guard let data=value.data(using:.utf8) else {return nil}; return try? JSONDecoder().decode(Self.self,from:data) }
}

public struct AppFailure: LocalizedError, Sendable {
    public var code: String
    public var message: String
    public init(_ code: String, _ message: String) { self.code=code; self.message=message }
    public var errorDescription: String? { message }
}
