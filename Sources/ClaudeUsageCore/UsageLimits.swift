import Foundation

/// One allowance window reported by Anthropic's OAuth usage endpoint.
///
/// `fraction` is always 0...1 regardless of the scale the payload arrived in —
/// see `UsageLimits.parse(payload:)` for why that needs deciding per payload
/// rather than per value.
public struct UsageLimit: Equatable {
    public let label: String
    public let fraction: Double
    public let resetsAt: Date?

    public init(label: String, fraction: Double, resetsAt: Date?) {
        self.label = label
        self.fraction = fraction
        self.resetsAt = resetsAt
    }

    /// Whether this window is still the one in force. A cached limit whose
    /// reset has passed describes an allowance that has since refilled, so it
    /// must not be shown as though it were current.
    public func isOpen(now: Date = Date()) -> Bool {
        guard let resetsAt else { return true }
        return resetsAt > now
    }
}

public enum UsageLimits {
    /// Parse the endpoint's payload into ordered windows: session first, then
    /// weekly, then any model-scoped windows.
    ///
    /// The scale is ambiguous per value and can only be settled per payload.
    /// The endpoint currently reports percentages (37.0, or 1.0 meaning one
    /// percent), while older payloads used fractions (0.37). Reading `1.0` on
    /// its own is genuinely undecidable, so if *any* value in the payload is
    /// >= 1 the whole payload is treated as percent-scaled and 1.0 renders as
    /// 1%, not 100%.
    public static func parse(payload: [String: Any]) -> [UsageLimit] {
        let session = bucket(payload, "five_hour")
        let weekly = bucket(payload, "seven_day_oauth_apps") ?? bucket(payload, "seven_day")

        var raw: [Any?] = [session?["utilization"], weekly?["utilization"]]
        if let entries = payload["limits"] as? [[String: Any]] {
            raw.append(contentsOf: entries.map { $0["percent"] })
        }
        let percentScale = raw.contains { value in
            guard let n = number(value) else { return false }
            return n >= 1
        }

        var limits: [UsageLimit] = []
        if let session, let fraction = normalize(session["utilization"], percentScale: percentScale) {
            limits.append(UsageLimit(label: "Session (5-hour)",
                                     fraction: fraction,
                                     resetsAt: resetDate(session["resets_at"])))
        }
        if let weekly, let fraction = normalize(weekly["utilization"], percentScale: percentScale) {
            limits.append(UsageLimit(label: "Weekly (7-day)",
                                     fraction: fraction,
                                     resetsAt: resetDate(weekly["resets_at"])))
        }
        return limits
    }

    // MARK: - Value handling

    static func bucket(_ payload: [String: Any], _ key: String) -> [String: Any]? {
        payload[key] as? [String: Any]
    }

    /// Numbers arrive as JSON numbers or as strings, sometimes with a trailing
    /// percent sign. Anything else is absent rather than zero — a missing
    /// window must not render as 0% used.
    static func number(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let s as String:
            let trimmed = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
            return Double(trimmed)
        default: return nil
        }
    }

    static func normalize(_ value: Any?, percentScale: Bool) -> Double? {
        guard let n = number(value), n >= 0 else { return nil }
        if percentScale || n > 1 { return min(1.0, n / 100.0) }
        return min(1.0, n)
    }

    /// `resets_at` is either an ISO-8601 string or an epoch stamp, and the
    /// stamp is seconds or milliseconds depending on the payload. Values below
    /// 1e12 are too small to be milliseconds in any plausible year, so they are
    /// read as seconds.
    static func resetDate(_ value: Any?) -> Date? {
        if let n = number(value), n > 0 {
            let seconds = n < 1e12 ? n : n / 1000
            return Date(timeIntervalSince1970: seconds)
        }
        guard let raw = (value as? String)?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}
