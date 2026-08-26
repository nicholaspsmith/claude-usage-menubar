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
    /// Low-contrast on purpose: it is context for the numbers above it, not a
    /// number itself, and should never compete with the percentages.
    private let age: NSTextField
    private let button: NSButton
    /// Stands in for the button while a refresh is in flight, so the click has
    /// visible consequence in a menu that is deliberately staying open.
    private let spinner = NSProgressIndicator()
    private let onRefresh: () -> Void

    init(title: String, age ageText: String, onRefresh: @escaping () -> Void) {
        self.onRefresh = onRefresh

        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label = NSTextField(labelWithString: title)
        label.font = font
        label.textColor = .secondaryLabelColor

        age = NSTextField(labelWithString: ageText)
        age.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        age.textColor = .tertiaryLabelColor
        age.alignment = .right

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

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        addSubview(label)
        addSubview(age)
        addSubview(button)
        addSubview(spinner)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let width = bounds.width
        let textHeight = ceil((label.font ?? NSFont.systemFont(ofSize: 11)).capHeight) + 6

        let glyph = NSRect(x: width - Self.rightPad - Self.buttonSize,
                           y: (bounds.height - Self.buttonSize) / 2,
                           width: Self.buttonSize,
                           height: Self.buttonSize)
        button.frame = glyph
        spinner.frame = glyph
        // The age takes only what it needs, hard against the button; the title
        // keeps the rest, so a long plan name shortens rather than colliding.
        let ageWidth = min(ceil(age.attributedStringValue.size().width) + 4,
                           max(0, button.frame.minX - Self.leftPad - 60))
        age.frame = NSRect(x: button.frame.minX - 8 - ageWidth,
                           y: (bounds.height - textHeight) / 2,
                           width: ageWidth,
                           height: textHeight)
        label.frame = NSRect(x: Self.leftPad,
                             y: (bounds.height - textHeight) / 2,
                             width: max(0, age.frame.minX - 8 - Self.leftPad),
                             height: textHeight)
    }

    /// Swap the glyph for a spinner while the poll runs.
    func setRefreshing(_ refreshing: Bool) {
        button.isHidden = refreshing
        if refreshing { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    @objc private func refreshClicked() {
        // The menu stays open, so the click has to show it did something and
        // the rows have to be replaced in place when the answer arrives —
        // otherwise the menu keeps rendering the snapshot it opened with.
        setRefreshing(true)
        onRefresh()
    }
}
