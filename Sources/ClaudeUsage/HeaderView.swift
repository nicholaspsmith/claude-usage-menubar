import AppKit

/// The menu's title row: plan on the left, a refresh button hard right.
///
/// Stretches to whatever width the menu settles on. NSMenu sizes item views to
/// the widest item, so a fixed-width view sits short of the right edge and the
/// refresh glyph floats in from the corner. The frame set here is only a
/// starting size; `layout()` is what actually positions anything.
final class HeaderView: NSView {
    static let minWidth: CGFloat = 268
    static let leftPad: CGFloat = 20
    static let rightPad: CGFloat = 14
    private static let buttonSize: CGFloat = 16

    private let label: NSTextField
    private let button: NSButton
    private let onRefresh: () -> Void

    init(title: String, onRefresh: @escaping () -> Void) {
        self.onRefresh = onRefresh

        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label = NSTextField(labelWithString: title)
        label.font = font
        label.textColor = .secondaryLabelColor

        button = NSButton(frame: .zero)
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: "arrow.clockwise",
                               accessibilityDescription: "Refresh")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "Refresh now"

        let textHeight = ceil(font.capHeight) + 6
        let rowHeight = max(textHeight, Self.buttonSize) + 8
        super.init(frame: NSRect(x: 0, y: 0, width: Self.minWidth, height: rowHeight))

        // Without this the view keeps its initial width and never reaches the
        // menu's right edge.
        autoresizingMask = [.width]
        button.target = self
        button.action = #selector(refreshClicked)
        addSubview(label)
        addSubview(button)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let width = bounds.width
        let textHeight = ceil((label.font ?? NSFont.systemFont(ofSize: 11)).capHeight) + 6

        button.frame = NSRect(x: width - Self.rightPad - Self.buttonSize,
                              y: (bounds.height - Self.buttonSize) / 2,
                              width: Self.buttonSize,
                              height: Self.buttonSize)
        label.frame = NSRect(x: Self.leftPad,
                             y: (bounds.height - textHeight) / 2,
                             width: max(0, button.frame.minX - 8 - Self.leftPad),
                             height: textHeight)
    }

    @objc private func refreshClicked() {
        // Dismiss first: the menu is rebuilt from the snapshot it opened with,
        // so leaving it up would show the old numbers until the next open and
        // read as a button that did nothing.
        enclosingMenuItem?.menu?.cancelTracking()
        onRefresh()
    }
}
