import Foundation
#if APPTRANSFER_PORTABLE_TESTS
import PortableTestSupport
#else
import XCTest
#endif
@testable import AppTransferCore

final class CoreTests:XCTestCase {
    private func temporary() throws -> URL {let url=FileManager.default.temporaryDirectory.appendingPathComponent("AppTransferTests-\(UUID().uuidString)");try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);addTeardownBlock{try? FileManager.default.removeItem(at:url)};return url}
    private func makeIPA(at root:URL,name:String="fixture",bundle:String="test.example.app",version:String="1.2",unsafe:Bool=false) throws -> URL {
        let output=root.appendingPathComponent(name+".ipa")
        let python=Process();python.executableURL=URL(fileURLWithPath:"/usr/bin/python3")
        python.arguments=["-c","import zipfile,plistlib,sys\np,b,v,u=sys.argv[1:]\nwith zipfile.ZipFile(p,'w',zipfile.ZIP_STORED) as z:\n z.writestr('Payload/Test.app/Info.plist',plistlib.dumps({'CFBundleIdentifier':b,'CFBundleDisplayName':'Fixture','CFBundleShortVersionString':v,'CFBundleVersion':'10','MinimumOSVersion':'15.0','UIDeviceFamily':[1]}))\n z.writestr('Payload/Test.app/SC_Info/Test.sinf',b'test')\n if u=='1': z.writestr('../outside',b'bad')\n",output.path,bundle,version,unsafe ? "1":"0"]
        try python.run();python.waitUntilExit();XCTAssertEqual(python.terminationStatus,0);return output
    }
    func testArchiveValidationAndExpectedIdentity() throws {
        let root=try temporary(),url=try makeIPA(at:root)
        let result=try IPAInspector.inspect(url,expected:AppDescriptor(bundleID:"test.example.app",name:"Fixture",version:"1.2",build:"10"))
        XCTAssertTrue(result.hasSinf);XCTAssertEqual(result.sha256.count,64);XCTAssertEqual(result.app.minimumOS,"15.0")
        XCTAssertThrowsError(try IPAInspector.inspect(url,expected:AppDescriptor(bundleID:"other",name:"Other",version:"1.2")))
        XCTAssertThrowsError(try IPAInspector.inspect(url,expected:AppDescriptor(bundleID:"test.example.app",name:"Fixture",version:"9.0")))
        XCTAssertThrowsError(try IPAInspector.inspect(makeIPA(at:root,name:"unsafe",unsafe:true)))
    }
    func testDamagedZIPNeverValidates() throws {
        let root=try temporary(),url=try makeIPA(at:root)
        var data=try Data(contentsOf:url)
        let needle=Data("<key>CFBundleIdentifier</key>".utf8)
        let range=try XCTUnwrap(data.range(of:needle));data[range.lowerBound+7] ^= 1;try data.write(to:url)
        XCTAssertThrowsError(try IPAInspector.inspect(url))
    }
    func testLibraryOwnershipAndBusyDeletion() async throws {
        let root=try temporary(),store=try LibraryStore(root:root.appendingPathComponent("Library"))
        let url=try makeIPA(at:root),inspection=try IPAInspector.inspect(url)
        let staged=await store.stagingURL();try FileManager.default.copyItem(at:url,to:staged)
        let first=try await store.add(stagedURL:staged,inspection:inspection,accountID:"account-one",email:"one@example.com")
        let secondStage=await store.stagingURL();try FileManager.default.copyItem(at:url,to:secondStage)
        let second=try await store.add(stagedURL:secondStage,inspection:inspection,accountID:"account-two",email:"two@example.com")
        XCTAssertNotEqual(first.id,second.id)
        let matching=await store.matching(inspection.app,accountID:"account-one");XCTAssertEqual(matching?.id,first.id)
        do {_ = try await store.delete(ids:[first.id],busy:[first.id]);XCTFail("Busy IPA deleted")}catch{XCTAssertEqual((error as? AppFailure)?.code,"libraryBusy")}
        let trash=root.appendingPathComponent("TestTrash");try FileManager.default.createDirectory(at:trash,withIntermediateDirectories:true)
        _ = try await store.delete(ids:[first.id],busy:[],recycle:{try FileManager.default.moveItem(at:$0,to:trash.appendingPathComponent($0.lastPathComponent))})
        let remaining=await store.snapshot();XCTAssertEqual(remaining.map(\.id),[second.id]);XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))
        let reopened=try LibraryStore(root:root.appendingPathComponent("Library"));let restored=await reopened.snapshot();XCTAssertEqual(restored.map(\.id),[second.id])
    }
    func testUnsafeManagedPathRejected() async throws {
        let root=try temporary(),store=try LibraryStore(root:root)
        let forged=LibraryItem(app:AppDescriptor(bundleID:"a",name:"A",version:"1"),accountID:nil,accountEmail:nil,relativePath:"../unrelated.ipa",bytes:1,sha256:"",hasSinf:false)
        do {_ = try await store.url(for:forged);XCTFail("Path traversal accepted")}catch{XCTAssertEqual((error as? AppFailure)?.code,"unsafePath")}
    }
    func testOperationRecoveryPreservesImmutableDestination() async throws {
        let root=try temporary(),store=try OperationStore(root:root)
        var job=TransferJob(app:AppDescriptor(bundleID:"a",name:"A",version:"1"),sourceDeviceID:"source",sourceName:"Same name",targetDeviceID:"target-1",targetName:"Same name");job.stage = .installing
        try await store.save(jobs:[job],history:[])
        let loaded=try await store.load();XCTAssertEqual(loaded.jobs[0].targetDeviceID,"target-1");XCTAssertEqual(loaded.jobs[0].stage,.installing)
        let path=root.appendingPathComponent("operations.json")
        var legacy=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:path)) as? [String:Any]);legacy.removeValue(forKey:"paused")
        try JSONSerialization.data(withJSONObject:legacy).write(to:path)
        let compatible=try await store.load();XCTAssertFalse(compatible.paused);XCTAssertEqual(compatible.jobs[0].targetDeviceID,"target-1")
    }

    func testLegacyQueueDatesAndStableNewestFirstPresentation() throws {
        let app=AppDescriptor(bundleID:"test.queue.order",name:"Queue fixture",version:"1")
        var first=TransferJob(app:app,sourceName:"Source",targetName:"Library")
        first.created=Date(timeIntervalSince1970:100)
        var second=first;second.id=UUID();second.created=Date(timeIntervalSince1970:200)
        var third=second;third.id=UUID()
        // Old persisted records have neither a retry date nor a presentation field.
        let encoded=try JSONEncoder().encode(first)
        var legacy=try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
        legacy.removeValue(forKey:"lastQueuedAt")
        let decoded=try JSONDecoder().decode(TransferJob.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertNil(decoded.lastQueuedAt);XCTAssertEqual(decoded.queuePresentationDate,first.created)
        let jobs=[decoded,second,third]
        XCTAssertEqual(QueuePresentation.newestFirst(jobs).map(\.id),[third.id,second.id,first.id])
        first.lastQueuedAt=Date(timeIntervalSince1970:300)
        first.updated=Date(timeIntervalSince1970:1)
        second.updated=Date(timeIntervalSince1970:9999)
        XCTAssertEqual(QueuePresentation.newestFirst([first,second,third]).map(\.id),[first.id,third.id,second.id],"Display order must use enqueue/retry recency, never progress update dates.")
    }
}
