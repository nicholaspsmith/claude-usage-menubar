// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import ClaudeUsageCore
import StatusItemKit

/// What Archimedes says, in a comic speech bubble under the menu bar whose
/// tail reaches up to his beak. One showing at a time, timed by
/// `GoOutside.frame`. A fresh panel each time: a long-lived one can silently
/// stop appearing after a wake or a screen change (Apollo's volume HUD).
final class SpeechBubble {
    var onClick: () -> Void = {}
    private var panel: NSPanel?
    private var animation: IconAnimation?

    var isShowing: Bool { panel != nil }

    /// Shows `text` with the tail's tip at `tip` (screen points): the bottom
    /// of the menu bar under the owl's beak. Nothing draws over the bar itself
    /// (macOS 27 composites it above every window), so the tail points up at
    /// the beak from just below it. The body is kept inside the screen.
    func show(text: String, tip: NSPoint, on screen: NSScreen) {
        hide()
        let view = BubbleView(text: text)
        view.onClick = { [weak self] in
            self?.hide()
            self?.onClick()
        }
        let body = view.bodySize
        let bodyTop = tip.y - BubbleView.tail
        let margin: CGFloat = 6
        let x = min(max(tip.x - body.width / 2, screen.frame.minX + margin), screen.frame.maxX - margin - body.width)
        view.tailX = tip.x - x
        let frame = NSRect(x: x, y: bodyTop - body.height, width: body.width, height: body.height + BubbleView.tail)

        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.animationBehavior = .none
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.contentView = view
        // Above every app's windows. Set last: making a panel floating, among
        // other things, resets its level.
        p.level = .popUpMenu
        p.alphaValue = 0
        p.orderFrontRegardless()
        panel = p

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let anim = IconAnimation(duration: GoOutside.duration, frame: { [weak p, weak view] t in
            guard let f = GoOutside.frame(at: t, reduceMotion: reduceMotion) else { return }
            p?.alphaValue = f.alpha
            view?.scale = f.scale
        }, completion: { [weak self] in self?.hide() })
        animation = anim
        anim.start()
    }

    func hide() {
        animation?.cancel()
        animation = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

/// The bubble: a white rounded body with a black outline and a tail up to
/// the tip, the whole drawing scaled about the tip as it bounces in.
private final class BubbleView: NSView {
    static let tail: CGFloat = 8
    var onClick: () -> Void = {}
    var tailX: CGFloat = 0 { didSet { needsDisplay = true } }
    var scale: Double = 1 { didSet { needsDisplay = true } }

    private let text: NSAttributedString
    private static let padding = NSSize(width: 12, height: 7)
    private static let tailWidth: CGFloat = 14
    private static let radius: CGFloat = 10
    private static let stroke: CGFloat = 1.5

    init(text: String) {
        self.text = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.black,
        ])
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The body, outline included, without the tail.
    var bodySize: NSSize {
        let t = text.size()
        return NSSize(width: ceil(t.width) + Self.padding.width * 2 + Self.stroke * 2,
                      height: ceil(t.height) + Self.padding.height * 2 + Self.stroke * 2)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func draw(_ dirtyRect: NSRect) {
        let body = bodySize
        let tip = NSPoint(x: tailX, y: body.height + Self.tail)
        NSGraphicsContext.current?.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: tip.x, yBy: tip.y)
        transform.scale(by: CGFloat(scale))
        transform.translateX(by: -tip.x, yBy: -tip.y)
        transform.concat()

        let inset = Self.stroke / 2
        let rect = NSRect(x: inset, y: inset, width: body.width - Self.stroke, height: body.height - Self.stroke)
        let shape = NSBezierPath(roundedRect: rect, xRadius: Self.radius, yRadius: Self.radius)
        // The tail leaves the body's top edge, kept clear of the rounded corners.
        let half = Self.tailWidth / 2
        let baseX = min(max(tailX, rect.minX + Self.radius + half), rect.maxX - Self.radius - half)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: baseX - half, y: rect.maxY - 1))
        tail.line(to: NSPoint(x: tip.x, y: tip.y - inset))
        tail.line(to: NSPoint(x: baseX + half, y: rect.maxY - 1))
        tail.close()
        shape.append(tail)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 3
        NSGraphicsContext.current?.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        shape.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
        NSColor.black.setStroke()
        shape.lineWidth = Self.stroke
        shape.stroke()
        // Cover the outline where the tail joins the body, so the two read as one shape.
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: baseX - half + 1.5, y: rect.maxY - 2.5, width: Self.tailWidth - 3, height: 3)).fill()

        let t = text.size()
        text.draw(at: NSPoint(x: (body.width - t.width) / 2, y: (body.height - t.height) / 2))
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
