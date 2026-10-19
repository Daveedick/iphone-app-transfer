import Foundation
#if APPTRANSFER_PORTABLE_TESTS
import PortableTestSupport
#else
import XCTest
#endif
@testable import AppTransferCore

private actor CoordinatorGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters; waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private actor CoordinatorDevice: DeviceBackend {
    struct Statistics: Sendable {
        var targets: [String]
        var maximumConcurrentInstalls: Int
        var readCounts: [String: Int]
    }
    private var phones: [String: Phone]
    private var inventory: [String: [AppDescriptor]]
    private let installationGate: CoordinatorGate?
    private let confirmInstallation: Bool
    private var targets: [String] = []
    private var activeInstalls = 0
    private var maximumConcurrentInstalls = 0
    private var reads: [String: Int] = [:]
    private var lastProgress: (@Sendable (JobStage, Double?) -> Void)?
    init(ids: [String] = ["target-a", "target-b"], installed: [String: [AppDescriptor]] = [:], gate: CoordinatorGate? = nil, confirm: Bool = true) {
        phones = Dictionary(uniqueKeysWithValues: ids.map { ($0, Phone(id: $0, name: "Same iPhone name", model: "iPhone", iOS: "18.5", freeBytes: 10_000_000_000)) })
        inventory = installed; installationGate = gate; confirmInstallation = confirm
    }
    func devices() async throws -> [Phone] { phones.values.sorted { $0.id < $1.id } }
    func applications(on deviceID: String) async throws -> [AppDescriptor] {
        reads[deviceID, default: 0] += 1
        guard phones[deviceID] != nil else { throw AppFailure("deviceUnavailable", "Reconnect the selected iPhone.") }
        return inventory[deviceID] ?? []
    }
    func install(_ url: URL, on deviceID: String, cancellation: CancellationFlag, progress: @escaping @Sendable (JobStage, Double?) -> Void) async throws {
        guard phones[deviceID] != nil else { throw AppFailure("deviceUnavailable", "Reconnect the selected iPhone.") }
        guard !cancellation.requested else { throw AppFailure("canceled", "Canceled before installation.") }
        lastProgress = progress
        targets.append(deviceID); activeInstalls += 1
        maximumConcurrentInstalls = max(maximumConcurrentInstalls, activeInstalls)
        defer { activeInstalls -= 1 }
        progress(.uploading, 1); progress(.installing, 0.25)
        if let installationGate { await installationGate.wait() }
        if confirmInstallation {
            let inspected = try IPAInspector.inspect(url)
            inventory[deviceID, default: []].append(inspected.app)
        }
        progress(.installing, 1)
    }
    func emitLateProgress() { lastProgress?(.installing, 0.1) }
    func connect(_ id: String) { phones[id] = Phone(id: id, name: "Same iPhone name", model: "iPhone", iOS: "18.5", freeBytes: 10_000_000_000) }
    func statistics() -> Statistics { Statistics(targets: targets, maximumConcurrentInstalls: maximumConcurrentInstalls, readCounts: reads) }
}

private actor CoordinatorStore: StoreBackend {
    struct Statistics: Sendable { var downloads: Int; var latestRequests: Int; var cancellations: Int; var outputPaths: [URL] }
    private let fixtures: [String: URL]
    private let failures: [String: String]
    private let gate: CoordinatorGate?
    private var downloads = 0
    private var latestRequests = 0
    private var cancellations = 0
    private var canceled = false
    private var outputPaths: [URL] = []
    private var lastProgress: (@Sendable (Double?) -> Void)?
    init(fixtures: [String: URL] = [:], failures: [String: String] = [:], gate: CoordinatorGate? = nil) { self.fixtures = fixtures; self.failures = failures; self.gate = gate }
    func accounts() async throws -> [AppleAccount] { [AppleAccount(id: "account-one", email: "fixture@example.invalid", authenticated: true)] }
    func versionInfo(app: AppDescriptor, accountID: String, latest: Bool) async throws -> AppDescriptor {
        if latest { latestRequests += 1 }
        if let code = failures[app.bundleID] { throw AppFailure(code, "Synthetic account failure.") }
        return app
    }
    func download(app: AppDescriptor, accountID: String, to url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws {
        lastProgress = progress
        downloads += 1; outputPaths.append(url); canceled = false
        guard let fixture = fixtures[app.bundleID] else { throw AppFailure("missingArchive", "Synthetic fixture missing.") }
        if let gate {
            try FileManager.default.copyItem(at: fixture, to: URL(fileURLWithPath: url.path + ".tmp"))
            progress(nil)
            await gate.wait()
            if canceled { throw AppFailure("canceled", "Synthetic download canceled.") }
        }
        try FileManager.default.copyItem(at: fixture, to: url)
        progress(1)
    }
    func emitLateProgress() { lastProgress?(0.1) }
    func cancelDownload() async { cancellations += 1; canceled = true; if let gate { await gate.open() } }
    func statistics() -> Statistics { Statistics(downloads: downloads, latestRequests: latestRequests, cancellations: cancellations, outputPaths: outputPaths) }
}

final class CoordinatorTests: XCTestCase {
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AppTransferCoordinator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func descriptor(_ suffix: String = "main") -> AppDescriptor {
        AppDescriptor(bundleID: "test.coordinator.\(suffix)", name: suffix, version: "1.2", build: "10", storeItemID: 123, externalVersionID: "1001")
    }
    private func fixture(_ app: AppDescriptor, root: URL) throws -> URL {
        let output = root.appendingPathComponent(app.bundleID + ".ipa")
        let script = """
        import plistlib, sys, zipfile
        path, bundle = sys.argv[1:]
        info = {'CFBundleIdentifier':bundle,'CFBundleDisplayName':'Fixture','CFBundleShortVersionString':'1.2','CFBundleVersion':'10','MinimumOSVersion':'15.0','UIDeviceFamily':[1]}
        metadata = {'itemId':123,'softwareVersionExternalIdentifier':1001,'apple-id':'fixture@example.invalid'}
        with zipfile.ZipFile(path, 'w', zipfile.ZIP_STORED) as archive:
            archive.writestr('Payload/Fixture.app/Info.plist', plistlib.dumps(info))
            archive.writestr('Payload/Fixture.app/SC_Info/Fixture.sinf', b'synthetic-license')
            archive.writestr('iTunesMetadata.plist', plistlib.dumps(metadata))
        """
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script, output.path, app.bundleID]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw AppFailure("fixture", "Could not create synthetic IPA.") }
        return output
    }
    private func coordinator(root: URL, device: CoordinatorDevice, store: CoordinatorStore) throws -> (TransferCoordinator, LibraryStore, OperationStore) {
        let library = try LibraryStore(root: root.appendingPathComponent("Library"))
        let persistence = try OperationStore(root: root.appendingPathComponent("State"))
        return (TransferCoordinator(device: device, store: store, library: library, persistence: persistence), library, persistence)
    }
    private func job(_ app: AppDescriptor, target: String? = nil, libraryID: UUID? = nil) -> TransferJob {
        TransferJob(app: app, sourceDeviceID: "source", sourceName: "Source", targetDeviceID: target, targetName: target ?? "Library", accountID: "account-one", accountEmail: "fixture@example.invalid", libraryID: libraryID)
    }
    @discardableResult private func waitFor(_ coordinator: TransferCoordinator, _ predicate: (QueueSnapshot) -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws -> QueueSnapshot {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            let snapshot = await coordinator.snapshot()
            if predicate(snapshot) { return snapshot }
            try await Task.sleep(nanoseconds: 5_000_000)
        } while Date() < deadline
        XCTFail("Coordinator did not reach the expected state.", file: file, line: line)
        throw AppFailure("testTimeout", "Coordinator wait timed out.")
    }
    private func waitUntilInstallStarted(_ device: CoordinatorDevice) async throws {
        let deadline = Date().addingTimeInterval(5)
        repeat { if !(await device.statistics()).targets.isEmpty { return }; try await Task.sleep(nanoseconds: 5_000_000) } while Date() < deadline
        throw AppFailure("testTimeout", "Install gate was not reached.")
    }

    func testOneDownloadReusedAcrossTargetsAndInstallsStaySequential() async throws {
        let root = try temporary(), app = descriptor(), gate = CoordinatorGate()
        let device = CoordinatorDevice(gate: gate), store = CoordinatorStore(fixtures: [app.bundleID: try fixture(app, root: root)])
        let (queue, library, _) = try coordinator(root: root, device: device, store: store)
        try await queue.start(); await queue.setPaused(true)
        await queue.enqueue(job(app, target: "target-a")); await queue.enqueue(job(app, target: "target-b")); await queue.setPaused(false)
        try await waitUntilInstallStarted(device)
        let blocked = await device.statistics()
        XCTAssertEqual(blocked.targets, ["target-a"], "Second destination started before the first installation finished.")
        await gate.open()
        let finished = try await waitFor(queue) { $0.jobs.count == 2 && $0.jobs.allSatisfy { $0.stage.terminal } && !$0.running }
        XCTAssertEqual(finished.jobs.map(\.stage), [.succeeded, .succeeded])
        let storeStats = await store.statistics(), deviceStats = await device.statistics(), items = await library.snapshot()
        XCTAssertEqual(storeStats.downloads, 1); XCTAssertEqual(items.count, 1)
        XCTAssertEqual(deviceStats.targets, ["target-a", "target-b"]); XCTAssertEqual(deviceStats.maximumConcurrentInstalls, 1)
        XCTAssertGreaterThanOrEqual(deviceStats.readCounts["target-a"] ?? 0, 2, "Installation was not independently read back.")
        XCTAssertGreaterThanOrEqual(deviceStats.readCounts["target-b"] ?? 0, 2)
    }

    func testLibraryOnlyDownloadNeverInstallsOnAnyDevice() async throws {
        let root = try temporary(), app = descriptor(), device = CoordinatorDevice()
        let store = CoordinatorStore(fixtures: [app.bundleID: try fixture(app, root: root)])
        let (queue, library, _) = try coordinator(root: root, device: device, store: store)
        try await queue.start(); await queue.enqueue(job(app))
        let finished = try await waitFor(queue) { $0.jobs.first?.stage == .succeeded && !$0.running }
        let stats = await device.statistics(), items = await library.snapshot(), downloads = await store.statistics()
        XCTAssertNil(finished.jobs[0].targetDeviceID); XCTAssertEqual(items.count, 1); XCTAssertEqual(downloads.downloads, 1)
        XCTAssertTrue(stats.targets.isEmpty); XCTAssertTrue(stats.readCounts.isEmpty)
    }

    func testEnqueueOutcomeIdentifiesAcceptedAndExistingJobWithoutRestampingDuplicate() async throws {
        let root=try temporary(),app=descriptor(),device=CoordinatorDevice(),store=CoordinatorStore()
        let (queue,_,persistence)=try coordinator(root:root,device:device,store:store)
        try await queue.start();await queue.setPaused(true)
        var pending=job(app);pending.lastQueuedAt=Date(timeIntervalSince1970:1)
        let accepted=await queue.enqueue(pending)
        let first=await queue.snapshot()
        let duplicate=await queue.enqueue(job(app))
        let after=await queue.snapshot(),saved=try await persistence.load(),statistics=await store.statistics()
        XCTAssertTrue(accepted.inserted);XCTAssertEqual(accepted.jobID,pending.id)
        XCTAssertFalse(duplicate.inserted);XCTAssertEqual(duplicate.jobID,pending.id)
        XCTAssertEqual(after.jobs.count,1);XCTAssertEqual(after.jobs[0].lastQueuedAt,first.jobs[0].lastQueuedAt)
        XCTAssertNotEqual(after.jobs[0].lastQueuedAt,pending.lastQueuedAt)
        XCTAssertEqual(saved.jobs[0].lastQueuedAt,after.jobs[0].lastQueuedAt)
        XCTAssertEqual(statistics.downloads,0)
        let rejectedRetry=await queue.retry(UUID());XCTAssertFalse(rejectedRetry)
    }

    func testRetryRecencySurvivesRelaunchWhileExecutionRemainsFIFO() async throws {
        let root=try temporary(),firstApp=descriptor("first-retry"),secondApp=descriptor("second-pending"),device=CoordinatorDevice()
        let store=CoordinatorStore(fixtures:[firstApp.bundleID:try fixture(firstApp,root:root),secondApp.bundleID:try fixture(secondApp,root:root)])
        let (queue,library,persistence)=try coordinator(root:root,device:device,store:store)
        var first=job(firstApp,target:"target-a");first.stage = .failed;first.lastQueuedAt=Date(timeIntervalSince1970:100)
        var second=job(secondApp,target:"target-b");second.lastQueuedAt=Date(timeIntervalSince1970:200)
        try await persistence.save(jobs:[first,second],history:[],paused:true)
        try await queue.start()
        let accepted=await queue.retry(first.id);XCTAssertTrue(accepted)
        let retried=await queue.snapshot()
        XCTAssertEqual(retried.jobs.map(\.id),[first.id,second.id],"Retry must not mutate the worker's FIFO order.")
        XCTAssertEqual(QueuePresentation.newestFirst(retried.jobs).map(\.id),[first.id,second.id])
        XCTAssertEqual(retried.jobs[1].lastQueuedAt,second.lastQueuedAt)
        let restored=TransferCoordinator(device:device,store:store,library:library,persistence:persistence)
        try await restored.start()
        let reopened=await restored.snapshot()
        XCTAssertEqual(reopened.jobs[0].lastQueuedAt,retried.jobs[0].lastQueuedAt)
        XCTAssertEqual(QueuePresentation.newestFirst(reopened.jobs).map(\.id),[first.id,second.id])
        await restored.setPaused(false)
        let finished=try await waitFor(restored){$0.jobs.allSatisfy{$0.stage == .succeeded} && !$0.running}
        let statistics=await device.statistics()
        XCTAssertEqual(statistics.targets,["target-a","target-b"])
        XCTAssertEqual(finished.jobs[0].lastQueuedAt,retried.jobs[0].lastQueuedAt)
    }

    func testDownloadProgressAndCompletionPreservePresentationOrder() async throws {
        let root=try temporary(),firstApp=descriptor("progress-first"),secondApp=descriptor("progress-second"),device=CoordinatorDevice(),gate=CoordinatorGate()
        let store=CoordinatorStore(fixtures:[firstApp.bundleID:try fixture(firstApp,root:root),secondApp.bundleID:try fixture(secondApp,root:root)],gate:gate)
        let (queue,_,_)=try coordinator(root:root,device:device,store:store)
        try await queue.start();await queue.setPaused(true)
        let first=job(firstApp),second=job(secondApp)
        await queue.enqueue(first);await queue.enqueue(second)
        let before=await queue.snapshot(),expected=[second.id,first.id]
        XCTAssertEqual(QueuePresentation.newestFirst(before.jobs).map(\.id),expected)
        await queue.setPaused(false)
        _ = try await waitFor(queue){$0.jobs[0].stage == .downloading}
        let activeRetry=await queue.retry(first.id);XCTAssertFalse(activeRetry)
        await store.emitLateProgress()
        let progress=try await waitFor(queue){$0.jobs[0].progress == 0.1}
        XCTAssertEqual(QueuePresentation.newestFirst(progress.jobs).map(\.id),expected)
        XCTAssertEqual(progress.jobs.map(\.lastQueuedAt),before.jobs.map(\.lastQueuedAt))
        await gate.open()
        let finished=try await waitFor(queue){$0.jobs.allSatisfy{$0.stage == .succeeded} && !$0.running}
        XCTAssertEqual(QueuePresentation.newestFirst(finished.jobs).map(\.id),expected)
        XCTAssertEqual(finished.jobs.map(\.lastQueuedAt),before.jobs.map(\.lastQueuedAt))
    }

    func testAccountFailuresWaitWhileIndependentJobsContinue() async throws {
        let root = try temporary(), licensed = descriptor("license"), expired = descriptor("expired"), valid = descriptor("valid"), missing = descriptor("missing")
        let device = CoordinatorDevice(), store = CoordinatorStore(fixtures: [valid.bundleID: try fixture(valid, root: root)], failures: [licensed.bundleID: "licenseRequired", expired.bundleID: "sessionExpired"])
        let (queue, _, _) = try coordinator(root: root, device: device, store: store)
        try await queue.start(); await queue.setPaused(true)
        await queue.enqueue(job(licensed)); await queue.enqueue(job(expired))
        var unassigned = job(missing); unassigned.accountID = nil; unassigned.accountEmail = nil
        await queue.enqueue(unassigned); await queue.enqueue(job(valid)); await queue.setPaused(false)
        let snapshot = try await waitFor(queue) { $0.jobs.count == 4 && $0.jobs.last?.stage == .succeeded && !$0.running }
        XCTAssertEqual(snapshot.jobs.map(\.stage), [.awaitingAccount, .awaitingAccount, .awaitingAccount, .succeeded])
        XCTAssertEqual(snapshot.jobs[0].errorCode, "licenseRequired"); XCTAssertEqual(snapshot.jobs[1].errorCode, "sessionExpired")
        let statistics = await store.statistics()
        XCTAssertEqual(statistics.downloads, 1); XCTAssertEqual(statistics.latestRequests, 0, "Account failures must not silently probe another app version.")
    }

    func testDisconnectNeverRetargetsAndRetryUsesOriginalIdentity() async throws {
        let root = try temporary(), app = descriptor(), device = CoordinatorDevice(ids: ["target-b"])
        let store = CoordinatorStore(fixtures: [app.bundleID: try fixture(app, root: root)])
        let (queue, _, _) = try coordinator(root: root, device: device, store: store), original = job(app, target: "target-a")
        try await queue.start(); await queue.enqueue(original)
        let waiting = try await waitFor(queue) { $0.jobs.first?.stage == .awaitingDevice && !$0.running }
        XCTAssertEqual(waiting.jobs[0].targetDeviceID, "target-a")
        let before = await device.statistics(); XCTAssertTrue(before.targets.isEmpty)
        await device.connect("target-a"); await queue.retry(original.id)
        let finished = try await waitFor(queue) { $0.jobs.first?.stage == .succeeded && !$0.running }
        let after = await device.statistics()
        XCTAssertEqual(finished.jobs[0].targetDeviceID, "target-a"); XCTAssertEqual(after.targets, ["target-a"])
    }

    func testRecoveryRequiresReadbackAndSkipsAlreadyInstalledApp() async throws {
        let root = try temporary(), app = descriptor(), device = CoordinatorDevice(installed: ["target-a": [app]]), store = CoordinatorStore()
        let (queue, _, persistence) = try coordinator(root: root, device: device, store: store)
        var interrupted = job(app, target: "target-a"); interrupted.stage = .installing
        try await persistence.save(jobs: [interrupted], history: [])
        try await queue.start()
        let recovered = await queue.snapshot()
        XCTAssertEqual(recovered.jobs[0].stage, .interrupted); XCTAssertEqual(recovered.jobs[0].targetDeviceID, "target-a")
        await queue.retry(interrupted.id)
        let verified = try await waitFor(queue) { $0.jobs.first?.stage == .skipped && !$0.running }
        let installs = await device.statistics(), downloads = await store.statistics()
        XCTAssertEqual(verified.jobs[0].targetDeviceID, "target-a"); XCTAssertTrue(installs.targets.isEmpty); XCTAssertEqual(downloads.downloads, 0)
        XCTAssertEqual(installs.readCounts["target-a"], 1)
    }

    func testQueuedLibraryReferenceBlocksDeletionUntilCanceled() async throws {
        let root = try temporary(), app = descriptor(), device = CoordinatorDevice(), store = CoordinatorStore()
        let (queue, library, _) = try coordinator(root: root, device: device, store: store)
        let fixtureURL = try fixture(app, root: root), staged = await library.stagingURL()
        try FileManager.default.copyItem(at: fixtureURL, to: staged)
        let item = try await library.add(stagedURL: staged, inspection: IPAInspector.inspect(fixtureURL), accountID: "account-one", email: "fixture@example.invalid")
        try await queue.start(); await queue.setPaused(true)
        let pending = job(app, target: "target-a", libraryID: item.id); await queue.enqueue(pending)
        do { _ = try await queue.removeLibraryItems([item.id]); XCTFail("Queued archive was deleted.") }
        catch { XCTAssertEqual((error as? AppFailure)?.code, "libraryBusy") }
        let path = try await library.url(for: item)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        await queue.cancel(pending.id)
        let busy = await queue.busyLibraryIDs(), snapshot = await queue.snapshot()
        XCTAssertFalse(busy.contains(item.id)); XCTAssertEqual(snapshot.jobs[0].stage, .canceled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path), "Canceling a queue item must not delete its archive.")
    }

    func testDownloadCancellationCleansBothStagingFilesAndNeverInstalls() async throws {
        let root = try temporary(), app = descriptor(), gate = CoordinatorGate(), device = CoordinatorDevice()
        let store = CoordinatorStore(fixtures: [app.bundleID: try fixture(app, root: root)], gate: gate)
        let (queue, library, _) = try coordinator(root: root, device: device, store: store), pending = job(app, target: "target-a")
        try await queue.start(); await queue.enqueue(pending)
        _ = try await waitFor(queue) { $0.jobs.first?.stage == .downloading }
        // The mock gate holds download until cancellation; cancelDownload opens it.
        await queue.cancel(pending.id)
        _ = try await waitFor(queue) { $0.jobs.first?.stage == .canceled && !$0.running }
        let statistics = await store.statistics(), items = await library.snapshot(), installations = await device.statistics()
        XCTAssertEqual(statistics.cancellations, 1); XCTAssertEqual(statistics.outputPaths.count, 1)
        for path in statistics.outputPaths {
            XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: path.path + ".tmp"))
        }
        XCTAssertTrue(items.isEmpty); XCTAssertTrue(installations.targets.isEmpty)
    }

    func testPausedQueueCanCancelPendingJobWithoutStartingIt() async throws {
        let root = try temporary(), first = descriptor("first"), second = descriptor("second"), device = CoordinatorDevice()
        let store = CoordinatorStore(fixtures: [second.bundleID: try fixture(second, root: root)])
        let (queue, _, _) = try coordinator(root: root, device: device, store: store), canceled = job(first)
        try await queue.start(); await queue.setPaused(true)
        await queue.enqueue(canceled); await queue.enqueue(job(second)); await queue.cancel(canceled.id)
        let paused = await queue.snapshot(), before = await store.statistics()
        XCTAssertTrue(paused.paused); XCTAssertEqual(paused.jobs.map(\.stage), [.canceled, .queued]); XCTAssertEqual(before.downloads, 0)
        await queue.setPaused(false)
        let finished = try await waitFor(queue) { $0.jobs.last?.stage == .succeeded && !$0.running }
        let after = await store.statistics()
        XCTAssertEqual(finished.jobs.map(\.stage), [.canceled, .succeeded]); XCTAssertEqual(after.downloads, 1)
    }

    func testPausedQueueRemainsPausedAfterRelaunchUntilExplicitResume() async throws {
        let root=try temporary(), app=descriptor(), device=CoordinatorDevice()
        let store=CoordinatorStore(fixtures:[app.bundleID:try fixture(app,root:root)])
        let (original,library,persistence)=try coordinator(root:root,device:device,store:store)
        try await original.start();await original.setPaused(true)
        let pending=job(app);await original.enqueue(pending)
        let restored=TransferCoordinator(device:device,store:store,library:library,persistence:persistence)
        try await restored.start()
        let before=await restored.snapshot(),statistics=await store.statistics()
        XCTAssertTrue(before.paused);XCTAssertEqual(before.jobs.first?.stage,.queued);XCTAssertEqual(statistics.downloads,0)
        await restored.setPaused(false)
        _ = try await waitFor(restored){$0.jobs.first?.stage == .succeeded && !$0.running}
        let after=await store.statistics();XCTAssertEqual(after.downloads,1)
    }

    func testSuccessfulInstallCallWithoutReadbackIsFailure() async throws {
        let root = try temporary(), app = descriptor(), device = CoordinatorDevice(confirm: false)
        let store = CoordinatorStore(fixtures: [app.bundleID: try fixture(app, root: root)])
        let (queue, _, _) = try coordinator(root: root, device: device, store: store)
        try await queue.start(); await queue.enqueue(job(app, target: "target-a"))
        let finished = try await waitFor(queue) { $0.jobs.first?.stage == .failed && !$0.running }
        XCTAssertEqual(finished.jobs[0].errorCode, "verificationFailed")
        let statistics = await device.statistics()
        XCTAssertEqual(statistics.targets, ["target-a"]); XCTAssertGreaterThanOrEqual(statistics.readCounts["target-a"] ?? 0, 2)
    }

    func testVanishedArchiveIsMarkedMissingAndCannotMatch() async throws {
        let root = try temporary(), app = descriptor(), device = CoordinatorDevice(), store = CoordinatorStore()
        let (_, library, _) = try coordinator(root: root, device: device, store: store)
        let original = try fixture(app, root: root), staged = await library.stagingURL()
        try FileManager.default.copyItem(at: original, to: staged)
        let item = try await library.add(stagedURL: staged, inspection: IPAInspector.inspect(original), accountID: "account-one", email: "fixture@example.invalid")
        let managed = try await library.url(for: item)
        try FileManager.default.removeItem(at: managed)
        let refreshed = await library.snapshot(), matching = await library.matching(app, accountID: "account-one")
        XCTAssertEqual(refreshed.count, 1); XCTAssertTrue(refreshed[0].missing)
        XCTAssertNil(matching, "A file removed after startup must not be reused as an available archive.")
    }

    func testPendingMatchingArchiveCannotBeDeletedBeforeBinding() async throws {
        let root = try temporary(), app = descriptor(), device = CoordinatorDevice(), store = CoordinatorStore()
        let (queue, library, _) = try coordinator(root: root, device: device, store: store)
        let original = try fixture(app, root: root), staged = await library.stagingURL()
        try FileManager.default.copyItem(at: original, to: staged)
        let item = try await library.add(stagedURL: staged, inspection: IPAInspector.inspect(original), accountID: "account-one", email: "fixture@example.invalid")
        try await queue.start(); await queue.setPaused(true)
        let pending = job(app, target: "target-a")
        XCTAssertNil(pending.libraryID)
        await queue.enqueue(pending)
        do { _ = try await queue.removeLibraryItems([item.id]); XCTFail("Matching archive was deleted while a queued job had not bound its library ID yet.") }
        catch { XCTAssertEqual((error as? AppFailure)?.code, "libraryBusy") }
        let managed = try await library.url(for: item), snapshot = await queue.snapshot()
        XCTAssertTrue(FileManager.default.fileExists(atPath: managed.path)); XCTAssertEqual(snapshot.jobs[0].stage, .queued)
        await queue.cancel(pending.id)
    }

    func testLateDownloadAndInstallProgressCannotRegressSuccess() async throws {
        let root = try temporary(), app = descriptor(), device = CoordinatorDevice()
        let store = CoordinatorStore(fixtures: [app.bundleID: try fixture(app, root: root)])
        let (queue, _, _) = try coordinator(root: root, device: device, store: store)
        try await queue.start(); await queue.enqueue(job(app, target: "target-a"))
        _ = try await waitFor(queue) { $0.jobs.first?.stage == .succeeded && !$0.running }
        await store.emitLateProgress(); await device.emitLateProgress()
        // This is a bounded negative-event observation window: callbacks enqueue
        // unstructured Tasks, so give them time to execute after terminal state.
        try await Task.sleep(nanoseconds: 50_000_000)
        let snapshot = await queue.snapshot(), installs = await device.statistics()
        XCTAssertEqual(snapshot.jobs[0].stage, .succeeded); XCTAssertNil(snapshot.jobs[0].progress)
        XCTAssertEqual(snapshot.history.count, 1); XCTAssertEqual(installs.targets, ["target-a"])
    }

}
