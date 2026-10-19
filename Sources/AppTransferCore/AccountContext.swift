import Foundation

public enum AccountSelectionReason: String, Codable, Sendable {
    case metadataOwner, defaultAccount, onlyAccount, explicit, unresolved
}

public struct AccountSelection: Sendable {
    public var account: AppleAccount?
    public var reason: AccountSelectionReason
    public init(account: AppleAccount?, reason: AccountSelectionReason) {
        self.account = account
        self.reason = reason
    }
}

public enum AccountResolver {
    /// Resolve once for both the preview and the queued job. Source metadata is
    /// only an account hint; Apple still checks the selected account's license.
    public static func resolve(for app: AppDescriptor, accounts: [AppleAccount], defaultAccountID: String?) -> AccountSelection {
        if let email = app.ownerEmail,
           let owner = accounts.first(where: { $0.authenticated && $0.email.caseInsensitiveCompare(email) == .orderedSame }) {
            return AccountSelection(account: owner, reason: .metadataOwner)
        }
        if let defaultAccountID {
            let selected = accounts.first { $0.id == defaultAccountID && $0.authenticated }
            return AccountSelection(account: selected, reason: selected == nil ? .unresolved : .defaultAccount)
        }
        if accounts.count == 1, accounts[0].authenticated {
            return AccountSelection(account: accounts[0], reason: .onlyAccount)
        }
        return AccountSelection(account: nil, reason: .unresolved)
    }
}

public enum ArchiveOrigin: String, Codable, Sendable {
    case appStore, imported, unknown
}

/// Describes evidence recorded for one actual IPA. None of these fields proves
/// a current license, successful activation, or the phone's iCloud identity.
public struct ArchiveAccountContext: Codable, Hashable, Sendable {
    public var origin: ArchiveOrigin
    public var downloadAccountID: String?
    public var downloadAccountEmail: String?
    public var metadataOwnerEmail: String?

    public init(origin: ArchiveOrigin, downloadAccountID: String? = nil, downloadAccountEmail: String? = nil, metadataOwnerEmail: String? = nil) {
        self.origin = origin
        self.downloadAccountID = downloadAccountID
        self.downloadAccountEmail = Self.nonempty(downloadAccountEmail)
        self.metadataOwnerEmail = Self.nonempty(metadataOwnerEmail)
    }

    public var hasAccountConflict: Bool {
        guard let downloadAccountEmail, let metadataOwnerEmail else { return false }
        return downloadAccountEmail.caseInsensitiveCompare(metadataOwnerEmail) != .orderedSame
    }

    public var suggestedAccountEmail: String? {
        guard !hasAccountConflict else { return nil }
        return metadataOwnerEmail ?? downloadAccountEmail
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
