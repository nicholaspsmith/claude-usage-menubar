import Foundation

/// Compact relative-age formatting: "12s" / "3m" / "1h" / "2d".
///
/// Same shape as the helper in apollo-monitor-menubar, extended with days —
/// a laptop that slept over a weekend should say "2d", not "63h".
public enum RelativeTime {
    public static func short(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3600)h" }
        return "\(s / 86_400)d"
    }

    /// "updated 3m ago", or "updated just now" inside the first few seconds —
    /// "updated 0s ago" reads like a stuck clock.
    public static func ago(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "never updated" }
        let elapsed = now.timeIntervalSince(date)
        // A clock that moved backwards (sleep, NTP correction) must not render
        // a negative age.
        guard elapsed >= 5 else { return "updated just now" }
        return "updated \(short(elapsed)) ago"
    }
}
