import AppKit
import StatusItemKit

/// The fill colour for a usage fraction.
///
/// Defined here rather than by changing StatusItemKit's `Severity.color`: that
/// ramp is shared with the other menu-bar apps in the suite, and a battery or
/// process meter turning purple is not what was asked for.
///
/// Only the resting state changes. The escalation to orange and red is the
/// meter's actual warning and stays — a bar that is the same colour at 5% and
/// 95% has stopped telling you the one thing you opened it for.
enum UsageColor {
    /// Light purple, a shade darker in light mode. The same lavender that
    /// reads well on a dark menu is too pale on a white one to keep the bar
    /// legible against its track.
    static let resting = NSColor(name: "usageResting") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 0.71, green: 0.56, blue: 0.93, alpha: 1.0)
            : NSColor(srgbRed: 0.55, green: 0.38, blue: 0.84, alpha: 1.0)
    }

    static func fill(fraction: Double, warnPct: Int) -> NSColor {
        let pct = Int((fraction * 100).rounded())
        switch Severity.level(pct: pct, warnPct: warnPct) {
        case .normal: return resting
        case .elevated: return .systemOrange
        case .high: return .systemRed
        }
    }
}
