import AppKit
import ClaudeUsageCore
import StatusItemKit

/// One allowance rendered as a labelled progress bar.
///
/// Stretches with the menu, sharing HeaderView's padding so the percentage
/// column and the refresh glyph land on the same right margin.
final class LimitBarView: NSView {
    private static let barHeight: CGFloat = 6
    private static let percentWidth: CGFloat = 52

    private let fraction: CGFloat
    private let color: NSColor
    private let name: NSTextField
    private let percent: NSTextField
    private let detail: NSTextField?

    init(limit: UsageLimit, warnPct: Int, resting: NSColor, now: Date = Date()) {
        self.fraction = CGFloat(max(0, min(1, limit.fraction)))
        self.color = UsageColor.fill(fraction: limit.fraction, warnPct: warnPct, resting: resting)

        let labelFont = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1)
        let detailFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        name = NSTextField(labelWithString: limit.label)
        name.font = labelFont
        name.textColor = .labelColor

        percent = NSTextField(labelWithString: LimitRow.percentText(limit))
        percent.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .semibold)
        percent.textColor = color
        percent.alignment = .right

        let resetText = LimitRow.resetText(limit, now: now)
        if resetText.isEmpty {
            detail = nil
        } else {
            let field = NSTextField(labelWithString: resetText)
            field.font = detailFont
            field.textColor = .secondaryLabelColor
            detail = field
        }

        let rowHeight = ceil(labelFont.capHeight) + 4
        let detailHeight = ceil(detailFont.capHeight) + 6
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: HeaderView.minWidth,
                                 height: rowHeight + Self.barHeight + detailHeight + 12))

        autoresizingMask = [.width]
        addSubview(name)
        addSubview(percent)
        if let detail { addSubview(detail) }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let inner = innerRect
        let rowHeight = ceil((name.font ?? .systemFont(ofSize: 12)).capHeight) + 4

        name.frame = NSRect(x: inner.minX, y: bounds.height - rowHeight - 4,
                            width: max(0, inner.width - Self.percentWidth), height: rowHeight)
        percent.frame = NSRect(x: inner.maxX - Self.percentWidth, y: bounds.height - rowHeight - 4,
                               width: Self.percentWidth, height: rowHeight)
        if let detail {
            let detailHeight = ceil((detail.font ?? .systemFont(ofSize: 11)).capHeight) + 6
            detail.frame = NSRect(x: inner.minX, y: 3, width: inner.width, height: detailHeight)
        }
        needsDisplay = true
    }

    private var innerRect: NSRect {
        NSRect(x: HeaderView.leftPad, y: 0,
               width: max(0, bounds.width - HeaderView.leftPad - HeaderView.rightPad),
               height: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let inner = innerRect
        let y = barYOrigin
        let radius = Self.barHeight / 2
        let track = NSRect(x: inner.minX, y: y, width: inner.width, height: Self.barHeight)

        NSColor.tertiaryLabelColor.withAlphaComponent(0.28).set()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        guard fraction > 0 else { return }
        // A non-zero fraction always paints at least a full cap's width, so a
        // sliver of usage reads as "some" rather than as nothing at all.
        let filledWidth = max(Self.barHeight, inner.width * fraction)
        color.set()
        NSBezierPath(roundedRect: NSRect(x: inner.minX, y: y, width: filledWidth, height: Self.barHeight),
                     xRadius: radius, yRadius: radius).fill()
    }

    private var barYOrigin: CGFloat {
        ceil(NSFont.systemFont(ofSize: NSFont.smallSystemFontSize).capHeight) + 10
    }
}
