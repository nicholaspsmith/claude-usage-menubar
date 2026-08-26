import Foundation

/// What the menu needs to render the limits section.
public struct LimitsSnapshot: Equatable {
    public var limits: [UsageLimit]
    public var planLabel: String
    /// Non-empty when the numbers are missing or stale, and why.
    public var statusText: String

    public init(limits: [UsageLimit] = [], planLabel: String = "", statusText: String = "") {
        self.limits = limits
        self.planLabel = planLabel
        self.statusText = statusText
    }
}

public enum UsageClient {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// Opening and shutting the menu must not turn into a request per flick.
    public static let minProbeInterval: TimeInterval = 15

    /// Fetch the current allowances, reusing a recent result and falling back
    /// to the last good one whenever a probe fails.
    ///
    /// The fallback is deliberately filtered by `isOpen`: a cached limit whose
    /// window has since reset describes an allowance that has already refilled,
    /// and showing it would be worse than showing nothing.
    public static func snapshot(credentials: ClaudeCredentials?,
                                cache: ProbeCache = ProbeCache(),
                                force: Bool = false,
                                now: Date = Date(),
                                fetch: (String) -> Result<[String: Any], ProbeError> = UsageClient.probe) -> LimitsSnapshot {
        let plan = credentials?.planLabel ?? ""
        let fallback = cache.load().filter { $0.isOpen(now: now) }

        guard let credentials else {
            return LimitsSnapshot(limits: fallback, planLabel: plan, statusText: "Not signed in")
        }
        if credentials.isExpired {
            return LimitsSnapshot(limits: fallback, planLabel: plan,
                                  statusText: "Sign-in expired — start Claude Code to refresh")
        }
        if !force, let age = cache.age(now: now), age < minProbeInterval, !fallback.isEmpty {
            return LimitsSnapshot(limits: fallback, planLabel: plan)
        }

        switch fetch(credentials.accessToken) {
        case .success(let payload):
            let limits = UsageLimits.parse(payload: payload)
            if !limits.isEmpty { cache.save(limits, now: now) }
            return LimitsSnapshot(limits: limits, planLabel: plan)
        case .failure(let error):
            return LimitsSnapshot(limits: fallback, planLabel: plan,
                                  statusText: fallback.isEmpty ? error.message : "")
        }
    }

    public enum ProbeError: Error, Equatable {
        case rateLimited(retryAfter: String)
        case status(Int)
        case transport

        public var message: String {
            switch self {
            case .rateLimited(let retryAfter):
                let suffix = retryAfter.isEmpty ? "" : " (retry after \(retryAfter)s)"
                return "Rate limited\(suffix)"
            case .status(let code): return "Usage endpoint returned \(code)"
            case .transport: return "Couldn't reach the usage endpoint"
            }
        }
    }

    public static func probe(token: String) -> Result<[String: Any], ProbeError> {
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var result: Result<[String: Any], ProbeError> = .failure(.transport)
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { done.signal() }
            guard let http = response as? HTTPURLResponse, let data else { return }
            guard http.statusCode == 200 else {
                let retryAfter = http.value(forHTTPHeaderField: "retry-after") ?? ""
                result = .failure(http.statusCode == 429 ? .rateLimited(retryAfter: retryAfter)
                                                         : .status(http.statusCode))
                return
            }
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            result = .success(json)
        }.resume()
        _ = done.wait(timeout: .now() + 12)
        return result
    }
}

/// Last-known limits, so a failed probe degrades to stale numbers rather than
/// a blank menu.
public final class ProbeCache {
    private let path: String

    public init(path: String? = nil) {
        self.path = path ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.nicholaspsmith.ClaudeUsage/limits.json").path
    }

    public func load() -> [UsageLimit] {
        guard let data = FileManager.default.contents(atPath: path),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rows = json["limits"] as? [[String: Any]]
        else { return [] }
        return rows.compactMap { row in
            guard let label = row["label"] as? String,
                  let fraction = row["fraction"] as? Double else { return nil }
            let resets = (row["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
            return UsageLimit(label: label, fraction: fraction, resetsAt: resets)
        }
    }

    public func age(now: Date = Date()) -> TimeInterval? {
        guard let data = FileManager.default.contents(atPath: path),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let fetched = json["fetchedAt"] as? Double else { return nil }
        return now.timeIntervalSince1970 - fetched
    }

    public func save(_ limits: [UsageLimit], now: Date = Date()) {
        let payload: [String: Any] = [
            "fetchedAt": now.timeIntervalSince1970,
            "limits": limits.map { limit -> [String: Any] in
                var row: [String: Any] = ["label": limit.label, "fraction": limit.fraction]
                if let resets = limit.resetsAt { row["resetsAt"] = resets.timeIntervalSince1970 }
                return row
            },
        ]
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
