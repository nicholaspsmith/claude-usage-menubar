import AppKit
import ClaudeUsageCore
import StatusItemKit

/// One allowance rendered as a labelled progress bar.
///
/// Uses explicit frames throughout: NSMenu reads a view's frame at insertion
/// time, before any auto-layout pass runs, so a constraint-only view would be
/// inserted at zero size and never appear.
final class LimitBarView: NSView {
    private static let width: CGFloat = 268
    private static let barHeight: CGFloat = 6
    private static let leftPad: CGFloat = 20
    private static let rightPad: CGFloat = 14

    private let fraction: CGFloat
    private let color: NSColor

    init(limit: UsageLimit, warnPct: Int, now: Date = Date()) {
        self.fraction = CGFloat(max(0, min(1, limit.fraction)))
        let pct = Int((limit.fraction * 100).rounded())
        self.color = Severity.level(pct: pct, warnPct: warnPct).color

        let labelFont = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1)
        let detailFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let rowHeight = ceil(labelFont.capHeight) + 4
        let detailHeight = ceil(detailFont.capHeight) + 6
        let totalHeight = rowHeight + Self.barHeight + detailHeight + 12

        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: totalHeight))

        let innerWidth = Self.width - Self.leftPad - Self.rightPad

        // Top line: the window's name on the left, its percentage hard right,
        // so the numbers form a column the eye can compare down.
        let name = NSTextField(labelWithString: limit.label)
        name.font = labelFont
        name.textColor = .labelColor
        name.frame = NSRect(x: Self.leftPad, y: totalHeight - rowHeight - 4,
                            width: innerWidth - 52, height: rowHeight)
        addSubview(name)

        let percent = NSTextField(labelWithString: LimitRow.percentText(limit))
        percent.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .semibold)
        percent.textColor = color
        percent.alignment = .right
        percent.frame = NSRect(x: Self.leftPad + innerWidth - 52, y: totalHeight - rowHeight - 4,
                               width: 52, height: rowHeight)
        addSubview(percent)

        // Bottom line: the reset countdown, or nothing when the window has
        // already refilled.
        let reset = LimitRow.resetText(limit, now: now)
        if !reset.isEmpty {
            let detail = NSTextField(labelWithString: reset)
            detail.font = detailFont
            detail.textColor = .secondaryLabelColor
            detail.frame = NSRect(x: Self.leftPad, y: 3, width: innerWidth, height: detailHeight)
            addSubview(detail)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let innerWidth = Self.width - Self.leftPad - Self.rightPad
        let y = barYOrigin
        let track = NSRect(x: Self.leftPad, y: y, width: innerWidth, height: Self.barHeight)
        let radius = Self.barHeight / 2

        NSColor.tertiaryLabelColor.withAlphaComponent(0.28).set()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        guard fraction > 0 else { return }
        // A non-zero fraction always paints at least a full cap's width, so a
        // sliver of usage reads as "some" rather than as nothing at all.
        let filledWidth = max(Self.barHeight, innerWidth * fraction)
        let filled = NSRect(x: Self.leftPad, y: y, width: filledWidth, height: Self.barHeight)
        color.set()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }

    private var barYOrigin: CGFloat {
        let detailFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        return ceil(detailFont.capHeight) + 6 + 4
    }
}
