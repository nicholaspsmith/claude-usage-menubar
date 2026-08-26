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
    public static let account = "root"

    public static func load() -> ClaudeCredentials? {
        guard let data = keychainData() ?? fileData() else { return nil }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }

        return ClaudeCredentials(
            accessToken: token,
            expiresAt: expiry(oauth["expiresAt"]),
            planLabel: planLabel(tier: oauth["rateLimitTier"] as? String ?? "",
                                subscription: oauth["subscriptionType"] as? String ?? "")
        )
    }

    static func keychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
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
