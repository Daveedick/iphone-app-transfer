import Foundation
#if APPTRANSFER_PORTABLE_TESTS
import PortableTestSupport
#else
import XCTest
#endif
@testable import AppTransferCore

final class AccountContextTests: XCTestCase {
    private let owner = AppleAccount(id: "owner", email: "owner@example.invalid", authenticated: true)
    private let other = AppleAccount(id: "other", email: "other@example.invalid", authenticated: true)
    private var app: AppDescriptor { AppDescriptor(bundleID: "test.accounts", name: "Fixture", version: "1", ownerEmail: "OWNER@example.invalid") }

    func testResolverUsesSameOwnerFirstPolicyForPreviewAndQueuedAccount() {
        let resolution = AccountResolver.resolve(for: app, accounts: [other, owner], defaultAccountID: other.id)
        XCTAssertEqual(resolution.account?.id, owner.id)
        XCTAssertEqual(resolution.reason, .metadataOwner)
        let job = TransferJob(app: app, sourceName: "Fixture iPhone", targetName: "Library", accountID: resolution.account?.id, accountEmail: resolution.account?.email, accountSelectionReason: resolution.reason)
        var noOwner = app; noOwner.ownerEmail = nil
        let nextResolution = AccountResolver.resolve(for: noOwner, accounts: [owner, other], defaultAccountID: other.id)
        XCTAssertEqual(nextResolution.account?.id, other.id)
        XCTAssertEqual(nextResolution.reason, .defaultAccount)
        XCTAssertEqual(job.accountID, owner.id, "Changing the default for another request must not change the queued account.")
    }

    func testResolverHandlesMissingExpiredAndAmbiguousAccounts() {
        XCTAssertNil(AccountResolver.resolve(for: app, accounts: [], defaultAccountID: nil).account)
        XCTAssertEqual(AccountResolver.resolve(for: app, accounts: [other], defaultAccountID: nil).reason, .onlyAccount)
        XCTAssertNil(AccountResolver.resolve(for: app, accounts: [other, AppleAccount(id: "third", email: "third@example.invalid", authenticated: true)], defaultAccountID: nil).account)
        var expired = owner; expired.authenticated = false
        let fallback = AccountResolver.resolve(for: app, accounts: [expired, other], defaultAccountID: other.id)
        XCTAssertEqual(fallback.account?.id, other.id)
        XCTAssertEqual(fallback.reason, .defaultAccount)
        XCTAssertNil(AccountResolver.resolve(for: app, accounts: [expired], defaultAccountID: nil).account)
        XCTAssertNil(AccountResolver.resolve(for: app, accounts: [other], defaultAccountID: "removed").account)
        var longEmail = other; longEmail.email = String(repeating: "long-account-", count: 12) + "@example.invalid"
        XCTAssertEqual(AccountResolver.resolve(for: app, accounts: [longEmail], defaultAccountID: nil).account?.email, longEmail.email)
    }

    func testImportedAndLegacyEmailNeverBecomeDownloadProvenance() throws {
        let imported = LibraryItem(app: app, accountID: nil, accountEmail: nil, relativePath: "fixture.ipa", bytes: 1, sha256: "fixture", hasSinf: true, origin: .imported)
        XCTAssertEqual(imported.archiveAccounts.origin, .imported)
        XCTAssertNil(imported.archiveAccounts.downloadAccountEmail)
        XCTAssertEqual(imported.archiveAccounts.metadataOwnerEmail, app.ownerEmail)
        var legacy = imported
        legacy.origin = nil; legacy.accountEmail = "legacy-owner@example.invalid"; legacy.app.ownerEmail = nil
        let decoded = try JSONDecoder().decode(LibraryItem.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(decoded.archiveAccounts.origin, .unknown)
        XCTAssertNil(decoded.archiveAccounts.downloadAccountID)
        XCTAssertNil(decoded.archiveAccounts.downloadAccountEmail)
        XCTAssertEqual(decoded.archiveAccounts.metadataOwnerEmail, "legacy-owner@example.invalid")
        let downloaded = LibraryItem(app: app, accountID: owner.id, accountEmail: owner.email, relativePath: "downloaded.ipa", bytes: 1, sha256: "fixture", hasSinf: true)
        XCTAssertEqual(downloaded.archiveAccounts.origin, .appStore)
        XCTAssertEqual(downloaded.archiveAccounts.downloadAccountEmail, owner.email)
        XCTAssertFalse(downloaded.archiveAccounts.hasAccountConflict)
    }

    func testArchiveConflictDoesNotSuggestOneConfirmedPhoneAccount() {
        let conflict = ArchiveAccountContext(origin: .appStore, downloadAccountID: other.id, downloadAccountEmail: other.email, metadataOwnerEmail: owner.email)
        XCTAssertTrue(conflict.hasAccountConflict)
        XCTAssertNil(conflict.suggestedAccountEmail)
        XCTAssertEqual(conflict.downloadAccountEmail, other.email)
        XCTAssertEqual(conflict.metadataOwnerEmail, owner.email)
        let unknown = ArchiveAccountContext(origin: .imported, metadataOwnerEmail: "  ")
        XCTAssertNil(unknown.suggestedAccountEmail)
        let metadataOnly = ArchiveAccountContext(origin: .imported, metadataOwnerEmail: owner.email)
        XCTAssertEqual(metadataOnly.suggestedAccountEmail, owner.email)
    }

    func testLegacyJobsAndActivityDecodeWithoutNewSnapshots() throws {
        let job = TransferJob(app: app, sourceName: "Source", targetName: "Library", accountID: owner.id, accountEmail: owner.email)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as? [String: Any])
        json.removeValue(forKey: "archiveAccounts"); json.removeValue(forKey: "accountSelectionReason")
        let oldJob = try JSONDecoder().decode(TransferJob.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(oldJob.archiveAccounts)
        XCTAssertNil(oldJob.accountSelectionReason)
        XCTAssertEqual(oldJob.accountEmail, owner.email)
        var activityJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ActivityEntry(job: job))) as? [String: Any])
        activityJSON.removeValue(forKey: "archiveAccounts"); activityJSON.removeValue(forKey: "installedOnDevice")
        let oldEntry = try JSONDecoder().decode(ActivityEntry.self, from: JSONSerialization.data(withJSONObject: activityJSON))
        XCTAssertNil(oldEntry.archiveAccounts)
        XCTAssertNil(oldEntry.installedOnDevice)
        XCTAssertEqual(oldEntry.accountEmail, owner.email)
    }
}
