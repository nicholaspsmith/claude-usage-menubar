import Foundation
import Security

/// Claude Code's stored OAuth login.
public struct ClaudeCredentials: Equatable {
    public let accessToken: String
    public let expiresAt: Date?
    public let planLabel: String

    public init(accessToken: String, expiresAt: Date?, planLabel: String) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.planLabel = planLabel
    }

    /// Only Claude Code itself can mint a fresh token — it refreshes the
    /// credential when it runs. A machine left alone long enough therefore
    /// finds the saved token lapsed, and the fix is to start Claude Code, not
    /// anything this app can do.
    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

public enum CredentialStore {
    /// macOS keeps the login in the Keychain rather than on disk. The item is
    /// owned by Claude Code, so the first read from a different binary raises
    /// the system's Keychain prompt; "Always Allow" makes it a one-time cost.
    public static let service = "Claude Code-credentials"

    /// Why the credential could not be read, so the menu can say something
    /// better than "Not signed in" when the real problem is a denied prompt.
    public enum LoadFailure: Equatable {
        case notFound
        case interactionNotAllowed
        case denied
        case unreadable
        case status(Int32)

        public var message: String {
            switch self {
            case .notFound: return "Claude Code not signed in on this Mac"
            case .interactionNotAllowed: return "Keychain locked — unlock it and refresh"
            case .denied: return "Keychain access denied — allow it in Keychain Access"
            case .unreadable: return "Credential unreadable"
            case .status(let code): return "Keychain error \(code)"
            }
        }
    }

    public static func load() -> ClaudeCredentials? { try? loadOrThrow() }

    /// The load, with the reason it failed preserved.
    public static func result() -> Result<ClaudeCredentials, LoadFailure> {
        do { return .success(try loadOrThrow()) }
        catch let failure as LoadFailure { return .failure(failure) }
        catch { return .failure(.unreadable) }
    }

    public static func loadOrThrow() throws -> ClaudeCredentials {
        var data = fileData()
        if data == nil {
            switch keychainData() {
            case .success(let found): data = found
            case .failure(let failure): throw failure
            }
        }
        guard let data else { throw LoadFailure.notFound }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw LoadFailure.unreadable }

        return ClaudeCredentials(
            accessToken: token,
            expiresAt: expiry(oauth["expiresAt"]),
            planLabel: planLabel(tier: oauth["rateLimitTier"] as? String ?? "",
                                subscription: oauth["subscriptionType"] as? String ?? "")
        )
    }

    /// Every item under this service, newest usable login first.
    ///
    /// Two things make this more than a one-shot lookup. The account name is
    /// not stable across machines — Claude Code stores it as "root" on one Mac
    /// here and as the login name on another — so the account cannot be part
    /// of the query. And a machine can hold SEVERAL items under this service:
    /// an old sign-in leaves its item behind when a new one is written, so
    /// this Mac carries an expired Pro token beside a live Max one. Asking for
    /// a single match returns an arbitrary one of them, which is how the app
    /// came to report an expired Pro plan for a signed-in Max account.
    ///
    /// So: take them all, and prefer the one that is actually still valid,
    /// falling back to the furthest-dated if none are.
    static func keychainData() -> Result<Data, LoadFailure> {
        // Two steps on purpose. macOS rejects kSecMatchLimitAll combined with
        // kSecReturnData for generic passwords — it returns errSecParam (-50)
        // before any ACL is consulted, which reads as a mysterious failure
        // rather than a coding error. So enumerate attributes to learn the
        // account names, then fetch each secret individually.
        let enumerateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var found: CFTypeRef?
        let status = SecItemCopyMatching(enumerateQuery as CFDictionary, &found)
        switch status {
        case errSecSuccess: break
        case errSecItemNotFound: return .failure(.notFound)
        case errSecInteractionNotAllowed: return .failure(.interactionNotAllowed)
        case errSecAuthFailed, errSecUserCanceled: return .failure(.denied)
        default: return .failure(.status(status))
        }

        let attributes = (found as? [[String: Any]]) ?? []
        let accounts = attributes.compactMap { $0[kSecAttrAccount as String] as? String }
        guard !accounts.isEmpty else { return .failure(.notFound) }

        var blobs: [Data] = []
        var lastFailure: LoadFailure?
        for account in accounts {
            switch secret(forAccount: account) {
            case .success(let data): blobs.append(data)
            case .failure(let failure): lastFailure = failure
            }
        }
        guard let best = bestCredential(among: blobs) else {
            return .failure(lastFailure ?? .unreadable)
        }
        return .success(best)
    }

    static func secret(forAccount account: String) -> Result<Data, LoadFailure> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return .failure(.unreadable) }
            return .success(data)
        case errSecItemNotFound: return .failure(.notFound)
        case errSecInteractionNotAllowed: return .failure(.interactionNotAllowed)
        case errSecAuthFailed, errSecUserCanceled: return .failure(.denied)
        default: return .failure(.status(status))
        }
    }

    /// Pick the live login out of however many the Keychain is holding.
    static func bestCredential(among blobs: [Data]) -> Data? {
        let now = Date()
        let dated = blobs.compactMap { blob -> (Data, Date)? in
            guard let root = (try? JSONSerialization.jsonObject(with: blob)) as? [String: Any],
                  let oauth = root["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String, !token.isEmpty
            else { return nil }
            return (blob, expiry(oauth["expiresAt"]) ?? .distantPast)
        }
        // A still-valid login always beats a lapsed one, however recent the
        // lapsed one is; among equals, the later expiry wins.
        let unexpired = dated.filter { $0.1 > now }
        return (unexpired.isEmpty ? dated : unexpired).max { $0.1 < $1.1 }?.0
    }

    /// The Linux/CI location, kept so the parsing path is exercisable off a Mac.
    static func fileData() -> Data? {
        let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path
        return FileManager.default.contents(atPath: dir + "/.credentials.json")
    }

    static func expiry(_ value: Any?) -> Date? {
        guard let ms = UsageLimits.number(value), ms > 0 else { return nil }
        // Recorded in milliseconds, but tolerate seconds the way the reset
        // stamps have to be tolerated.
        return Date(timeIntervalSince1970: ms < 1e12 ? ms : ms / 1000)
    }

    /// A display-safe plan name. Nothing else from the credential store is
    /// allowed to travel anywhere near the UI — the token's only destination
    /// is the Authorization header of the usage probe.
    public static func planLabel(tier: String, subscription: String) -> String {
        if let range = tier.range(of: #"max_(\d+x)"#, options: [.regularExpression, .caseInsensitive]) {
            let multiplier = tier[range].replacingOccurrences(of: "max_", with: "", options: .caseInsensitive)
            return "Max " + multiplier
        }
        guard !subscription.isEmpty else { return "" }
        return subscription.prefix(1).uppercased() + subscription.dropFirst().lowercased()
    }
}

extension CredentialStore.LoadFailure: Error {}

extension Result where Failure == CredentialStore.LoadFailure {
    /// The human-facing reason, or nil when this is a success.
    public var failureMessage: String? {
        if case .failure(let failure) = self { return failure.message }
        return nil
    }
}
