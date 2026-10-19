import Foundation

/// A deliberately small assertion adapter for CLT-only verification. This is not
/// XCTest and is never linked into the application or the normal XCTest target.
public enum PortableAssertions {
    private static let lock = NSLock()
    private static var failures = 0
    private static var assertions = 0
    public static func counts() -> (assertions: Int, failures: Int) {
        lock.lock(); defer { lock.unlock() }; return (assertions, failures)
    }
    public static func check(_ succeeded: Bool, _ detail: String, file: StaticString, line: UInt) {
        lock.lock(); assertions += 1
        if !succeeded { failures += 1; print("ASSERTION FAILED \(file):\(line): \(detail)") }
        lock.unlock()
    }
    public static func recordError(_ error: Error, context: String, file: StaticString = #filePath, line: UInt = #line) {
        check(false, "\(context): \(error)", file: file, line: line)
    }
}

open class PortableTestCase {
    private let lock = NSLock()
    private var teardownBlocks: [() async throws -> Void] = []
    public init() {}
    public func addTeardownBlock(_ block: @escaping () throws -> Void) {
        lock.lock(); teardownBlocks.append { try block() }; lock.unlock()
    }
    public func addAsyncTeardownBlock(_ block: @escaping () async throws -> Void) {
        lock.lock(); teardownBlocks.append(block); lock.unlock()
    }
    private func takeTeardowns() -> [() async throws -> Void] {
        lock.lock(); defer { lock.unlock() }
        let blocks = Array(teardownBlocks.reversed()); teardownBlocks.removeAll(); return blocks
    }
    public func runTeardowns() async {
        for block in takeTeardowns() {
            do { try await block() }
            catch { PortableAssertions.recordError(error, context: "Teardown failed") }
        }
    }
}

/// Source compatibility for shared test bodies only; no XCTest discovery/runtime.
public typealias XCTestCase = PortableTestCase

public func XCTFail(_ message: String = "Failed", file: StaticString = #filePath, line: UInt = #line) {
    PortableAssertions.check(false, message, file: file, line: line)
}
public func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { PortableAssertions.check(try expression(), message.isEmpty ? "Expected true" : message, file: file, line: line) }
    catch { PortableAssertions.recordError(error, context: "Boolean assertion threw", file: file, line: line) }
}
public func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { PortableAssertions.check(try !expression(), message.isEmpty ? "Expected false" : message, file: file, line: line) }
    catch { PortableAssertions.recordError(error, context: "Boolean assertion threw", file: file, line: line) }
}
public func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { let a = try lhs(), b = try rhs(); PortableAssertions.check(a == b, "Expected \(a) == \(b). \(message)", file: file, line: line) }
    catch { PortableAssertions.recordError(error, context: "Equality assertion threw", file: file, line: line) }
}
public func XCTAssertNotEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { let a = try lhs(), b = try rhs(); PortableAssertions.check(a != b, "Expected unequal values. \(message)", file: file, line: line) }
    catch { PortableAssertions.recordError(error, context: "Inequality assertion threw", file: file, line: line) }
}
public func XCTAssertNil<T>(_ expression: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { PortableAssertions.check(try expression() == nil, "Expected nil. \(message)", file: file, line: line) }
    catch { PortableAssertions.recordError(error, context: "Nil assertion threw", file: file, line: line) }
}
public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { let a = try lhs(), b = try rhs(); PortableAssertions.check(a >= b, "Expected \(a) >= \(b). \(message)", file: file, line: line) }
    catch { PortableAssertions.recordError(error, context: "Ordering assertion threw", file: file, line: line) }
}
public func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); PortableAssertions.check(false, "Expected an error. \(message)", file: file, line: line) }
    catch { PortableAssertions.check(true, "", file: file, line: line) }
}
private struct UnwrapFailure: Error {}
public func XCTUnwrap<T>(_ expression: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    let result = try expression()
    guard let result else { PortableAssertions.check(false, "Unwrap produced nil. \(message)", file: file, line: line); throw UnwrapFailure() }
    PortableAssertions.check(true, "", file: file, line: line); return result
}
