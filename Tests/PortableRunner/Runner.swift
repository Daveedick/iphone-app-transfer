import Foundation
import PortableTestSupport

@main struct PortableRunner {
    private static var executed = 0
    private static var failedTests = 0
    static func execute<T: PortableTestCase>(_ name: String, instance: T, body: (T) async throws -> Void) async {
        let before = PortableAssertions.counts().failures
        do { try await body(instance) }
        catch { PortableAssertions.recordError(error, context: "\(name) threw") }
        // Teardowns always execute, including after a thrown assertion/test error.
        await instance.runTeardowns()
        let failed = PortableAssertions.counts().failures > before
        executed += 1; if failed { failedTests += 1 }
        print("\(failed ? "FAIL" : "PASS") \(name)")
    }
    static func main() async {
        if CommandLine.arguments.contains("--self-check-failure") {
            struct ExpectedTeardownError: Error {}
            let instance = PortableTestCase()
            instance.addAsyncTeardownBlock { throw ExpectedTeardownError() }
            await execute("negative harness self-check", instance: instance) { _ in XCTAssertTrue(false, "Intentional failure must produce exit 1") }
            exit(PortableAssertions.counts().failures == 2 ? 1 : 2)
        }
        print("PORTABLE CLT HARNESS — shared Core/Coordinator tests; this is not XCTest")
        guard RegisteredTests.count > 0 else { print("FAIL: no tests registered"); exit(1) }
        await RegisteredTests.runAll()
        let counts = PortableAssertions.counts()
        print("Portable result: \(executed) tests, \(failedTests) failed tests, \(counts.assertions) assertions, \(counts.failures) failures")
        guard executed == RegisteredTests.count else { print("FAIL: registered test count mismatch"); exit(1) }
        exit(counts.failures == 0 ? 0 : 1)
    }
}
