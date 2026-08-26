import AppKit
import StatusItemKit

/// The fill colour for a usage fraction.
///
/// The resting colour is the user's choice (menu ▸ Icon); only the escalation
/// is fixed. Orange at 50% and red at 80% are the meter's actual warning and
/// are deliberately not configurable — a bar that stays one colour from 5% to
/// 95% has stopped telling you the one thing you opened it for.
enum UsageColor {
    /// Light purple, the app's out-of-the-box resting colour.
    static let defaultResting = MeterColor.color(fromHex: "#B18EEE") ?? .systemPurple

    static func fill(fraction: Double, warnPct: Int, resting: NSColor) -> NSColor {
        let pct = Int((fraction * 100).rounded())
        switch Severity.level(pct: pct, warnPct: warnPct) {
        case .normal: return resting
        case .elevated: return .systemOrange
        case .high: return .systemRed
        }
    }
}
