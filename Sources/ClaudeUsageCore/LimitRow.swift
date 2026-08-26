import Foundation

/// Presentation of one allowance row, kept out of the app target so the
/// formatting is testable without AppKit.
public enum LimitRow {
    public static func percentText(_ limit: UsageLimit) -> String {
        "\(Int((limit.fraction * 100).rounded()))%"
    }

    /// "resets in 2h 14m", or empty when there is no future reset to report.
    /// A window whose reset has passed says nothing rather than counting up.
    public static func resetText(_ limit: UsageLimit, now: Date = Date()) -> String {
        guard let resets = limit.resetsAt else { return "" }
        let remaining = resets.timeIntervalSince(now)
        guard remaining > 0 else { return "" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            return "resets in \(days)d \(hours % 24)h"
        }
        return hours > 0 ? "resets in \(hours)h \(minutes)m" : "resets in \(minutes)m"
    }
}
