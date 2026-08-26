import AppKit

/// The menu's title row: plan on the left, a refresh button hard right.
///
/// Explicit frames, like every other menu-item view here — NSMenu reads the
/// frame at insertion time, before auto-layout runs.
final class HeaderView: NSView {
    /// Matches LimitBarView so the refresh glyph lines up with the percentage
    /// column beneath it rather than floating at its own margin.
    static let width: CGFloat = 268
    private static let leftPad: CGFloat = 20
    private static let rightPad: CGFloat = 14

    private let onRefresh: () -> Void

    init(title: String, onRefresh: @escaping () -> Void) {
        self.onRefresh = onRefresh

        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        let buttonSize: CGFloat = 16
        let textHeight = ceil(font.capHeight) + 6
        let rowHeight = max(textHeight, buttonSize) + 8

        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: rowHeight))

        let label = NSTextField(labelWithString: title)
        label.font = font
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: Self.leftPad,
                             y: (rowHeight - textHeight) / 2,
                             width: Self.width - Self.leftPad - Self.rightPad - buttonSize - 8,
                             height: textHeight)
        addSubview(label)

        let button = NSButton(frame: NSRect(x: Self.width - Self.rightPad - buttonSize,
                                            y: (rowHeight - buttonSize) / 2,
                                            width: buttonSize,
                                            height: buttonSize))
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: "arrow.clockwise",
                               accessibilityDescription: "Refresh")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "Refresh now"
        button.target = self
        button.action = #selector(refreshClicked)
        addSubview(button)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func refreshClicked() {
        // Dismiss first: the menu is rebuilt from the snapshot it opened with,
        // so leaving it up would show the old numbers until the next open and
        // read as a button that did nothing.
        enclosingMenuItem?.menu?.cancelTracking()
        onRefresh()
    }
}
