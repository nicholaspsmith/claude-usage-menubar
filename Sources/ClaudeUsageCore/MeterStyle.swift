import Foundation

/// Which meter shape draws the menu-bar icon.
///
/// Every case has to be able to show a proportion — the icon's whole job is
/// the session allowance at a glance — so `dot`, which can only carry colour,
/// is deliberately not offered here.
public enum MeterStyle: String, CaseIterable, Equatable {
    case arc
    case gauge
    case pie
    case wedge

    public static let `default` = MeterStyle.arc
    public static let defaultsKey = "MeterStyle"

    public var title: String {
        switch self {
        case .arc: return "Arc"
        case .gauge: return "Gauge"
        case .pie: return "Pie"
        case .wedge: return "Wedge"
        }
    }

    /// Unknown values fall back rather than trapping: a persisted preference
    /// outlives the build that wrote it, and a style removed in a later version
    /// must not leave the app unable to draw an icon at all.
    public static func from(_ raw: String?) -> MeterStyle {
        guard let raw, let style = MeterStyle(rawValue: raw) else { return .default }
        return style
    }
}

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
