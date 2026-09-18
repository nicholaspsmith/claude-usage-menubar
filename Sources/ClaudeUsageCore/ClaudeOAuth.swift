import CryptoKit
import Foundation

/// The claude.ai sign-in, done the way Claude Code does it.
///
/// Claude Code is a public OAuth client: a fixed client id, PKCE, and a
/// redirect to a port on localhost that the CLI listens on for the moment it
/// takes the browser to come back. Every constant here is read out of the
/// CLI (2.1.274) rather than remembered, because the endpoints have moved
/// before — `console.anthropic.com` became `platform.claude.com` — and a
/// stale one fails with a page, not an error code.
///
/// This app asks for `user:profile` and nothing else. The usage endpoint
/// needs no more, and a token that could run inference or mint API keys has
/// no business sitting in a menu-bar app's Keychain item.
public enum ClaudeOAuth {
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let authorizeBase = URL(string: "https://claude.com/cai/oauth/authorize")!
    public static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    public static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    public static let scopes = ["user:profile"]

    /// One attempt's secrets: the PKCE verifier and the state the callback
    /// has to echo. Both are thrown away when the attempt ends, however it ends.
    public struct Exchange: Equatable {
        public let verifier: String
        public let state: String

        public init(verifier: String, state: String) {
            self.verifier = verifier
            self.state = state
        }

        public static func fresh() -> Exchange {
            Exchange(verifier: randomToken(), state: randomToken())
        }

        /// 32 random bytes as base64url, which is what the CLI sends too.
        static func randomToken() -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            return base64URL(Data(bytes))
        }
    }

    /// S256: the challenge is the SHA-256 of the verifier, base64url, no padding.
    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func redirectURI(port: UInt16) -> String { "http://localhost:\(port)/callback" }

    /// Where to send the browser.
    public static func authorizeURL(for exchange: Exchange, port: UInt16) -> URL {
        var components = URLComponents(url: authorizeBase, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI(port: port)),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge(for: exchange.verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: exchange.state),
        ]
        return components.url!
    }

    // MARK: - The callback

    public enum CallbackFailure: Error, Equatable {
        /// A request for something other than `/callback` — a favicon, say.
        case notTheCallback
        /// The browser came back without a code, or with an `error` parameter.
        case denied(String)
        /// Somebody else's redirect, or a replay: not the state we sent.
        case stateMismatch
    }

    /// The code out of the request line the browser sends back, checked
    /// against the state we issued. `target` is the path-and-query of an
    /// HTTP request, e.g. `/callback?code=…&state=…`.
    public static func code(fromRequestTarget target: String, expectedState: String) -> Result<String, CallbackFailure> {
        guard let components = URLComponents(string: "http://localhost" + target),
              components.path == "/callback"
        else { return .failure(.notTheCallback) }
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        if let error = query["error"] { return .failure(.denied(error)) }
        guard let code = query["code"], !code.isEmpty else { return .failure(.denied("no code")) }
        guard query["state"] == expectedState else { return .failure(.stateMismatch) }
        return .success(code)
    }

    // MARK: - Tokens

    public struct Tokens: Equatable {
        public let accessToken: String
        public let refreshToken: String?
        public let expiresAt: Date?

        public init(accessToken: String, refreshToken: String?, expiresAt: Date?) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
        }

        /// The token endpoint's reply. `expires_in` is seconds from now.
        public init?(json: [String: Any], now: Date = Date()) {
            guard let access = json["access_token"] as? String, !access.isEmpty else { return nil }
            accessToken = access
            refreshToken = json["refresh_token"] as? String
            expiresAt = UsageLimits.number(json["expires_in"]).map { now.addingTimeInterval($0) }
        }
    }

    static func jsonRequest(_ url: URL, body: [String: Any]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    public static func exchangeRequest(code: String, for exchange: Exchange, port: UInt16) -> URLRequest {
        jsonRequest(tokenURL, body: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI(port: port),
            "client_id": clientID,
            "code_verifier": exchange.verifier,
            "state": exchange.state,
        ])
    }

    public static func refreshRequest(refreshToken: String) -> URLRequest {
        jsonRequest(tokenURL, body: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "scope": scopes.joined(separator: " "),
        ])
    }

    public static func profileRequest(accessToken: String) -> URLRequest {
        var request = URLRequest(url: profileURL, timeoutInterval: 10)
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    // MARK: - The plan

    /// What the profile endpoint says the account is on, in the two fields
    /// Claude Code stores beside its token so `planLabel` reads both alike.
    public struct Plan: Equatable {
        public let rateLimitTier: String
        public let subscriptionType: String

        public init(rateLimitTier: String, subscriptionType: String) {
            self.rateLimitTier = rateLimitTier
            self.subscriptionType = subscriptionType
        }

        public init(profile: [String: Any]) {
            let account = profile["account"] as? [String: Any] ?? [:]
            let organization = profile["organization"] as? [String: Any] ?? [:]
            rateLimitTier = organization["rate_limit_tier"] as? String ?? ""
            if account["has_claude_max"] as? Bool == true {
                subscriptionType = "max"
            } else if account["has_claude_pro"] as? Bool == true {
                subscriptionType = "pro"
            } else {
                // "claude_max" → "max"; anything else is shown as it comes.
                let type = organization["organization_type"] as? String ?? ""
                subscriptionType = type.hasPrefix("claude_") ? String(type.dropFirst("claude_".count)) : type
            }
        }
    }
}
