// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import ClaudeUsageCore
import StatusItemKit

/// Everything one poll produces. Held whole so the menu renders a single
/// consistent moment rather than a mix of two polls.
private struct Snapshot {
    var limits = LimitsSnapshot()
    var sessions: [ClaudeSession] = []
    /// When this snapshot was taken, for the header's age line.
    var updatedAt: Date?
}

final class App: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController!
    /// Steps aside while Curtain reveals its hidden block — the bar has no
    /// spare room, and a reveal borrows slots from apps that cooperate.
    private var yieldClient: YieldClient!
    private var latest = Snapshot()
    /// The menu while it is on screen. A refresh no longer dismisses it, so a
    /// finished poll has to replace the rows of the menu the user is still
    /// looking at; NSMenu redraws when its items change under it.
    private weak var liveMenu: NSMenu?
    private weak var liveHeader: HeaderView?

    /// Shape, user-chosen, from StatusItemKit. The geometric meters are always
    /// fed the session fraction — the five-hour window is the one that actually
    /// stops work — while the owl shows both windows at once, either way
    /// round (`MenuPreferences.eyePerWindow`).
    /// Colour, by default, is data: the owl's pupils and the menu's bars are
    /// `MeterColor.health` of a fraction, dark green (#005401) when a window is
    /// fresh, reddening to #FF5401 when it is spent; the geometric meters use
    /// `MeterColor.usage`, cyan to red. Under Icon the user can pick a
    /// `ColorPair` instead: one fixed colour for the session, one for the week.
    private let appearance = MeterAppearance(defaultStyle: .character)
    private var colors = ColorPair.stored()
    private lazy var appearanceMenu = AppearanceMenu(appearance: appearance,
                                                     styles: MeterStyle.proportional + [.character],
                                                     characterTitle: "Owl",
                                                     offersColour: false) { [weak self] in
        guard let self else { return }
        self.render(self.latest)
    }

    // Polling does network I/O and walks the transcript tree, so it runs off
    // the main thread. These are main-thread only: a refresh asked for while
    // one is in flight is coalesced into a single follow-up rather than
    // stacking requests against a rate-limited endpoint.
    private let pollQueue = DispatchQueue(label: "com.nicholaspsmith.ClaudeUsage.poll")
    private var pollInFlight = false
    private var pollPending = false
    private var forceNext = false

    /// The owl blinks once a minute, taking its turn with the other animated
    /// mascots (`MinuteCue`).
    private var minuteCue: MinuteCue!
    private lazy var blinkAnimation = IconAnimation(duration: Blink.duration, frame: { [weak self] t in
        self?.blinkClosure = CGFloat(Blink.closure(at: t) ?? 0)
        if let self { self.render(self.latest) }
    }, completion: { [weak self] in
        self?.blinkClosure = 0
        if let self { self.render(self.latest) }
    })
    /// How shut the lids are mid-blink, layered over the session droop.
    private var blinkClosure: CGFloat = 0

    /// "Dude…go outside!" (`GoOutside`): checked on the minute, shown under
    /// the owl's beak until clicked.
    private let bubble = SpeechBubble()
    private var bubbleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusItemController(
            pollInterval: 60,
            onPoll: { [weak self] in self?.poll() },
            onBuildMenu: { [weak self] menu in self?.buildMenu(menu) },
            autosaveName: "ClaudeUsage"
        )
        // NSMenu has no "is open" flag worth trusting, so track the tracking.
        NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
        ) { [weak self] note in
            // Fires for every menu, submenus included. Clearing on the Icon
            // submenu closing would silently kill live updates for the rest of
            // the session, so only the root menu counts.
            guard let self, (note.object as? NSMenu) === self.liveMenu else { return }
            self.liveMenu = nil
            self.liveHeader = nil
        }

        yieldClient = YieldClient(item: controller)
        yieldClient.start()
        controller.start()

        minuteCue = MinuteCue { [weak self] in
            // Only the owl has lids, and shut ones don't blink.
            guard let self, self.appearance.style == .character, !GoOutside.eyesShut(now: Date()) else { return }
            self.blinkAnimation.start()
        }
        minuteCue.start()

        bubble.onClick = { [weak self] in self?.bubbleClicked() }
        scheduleBubble()
        // `--go-outside-preview`: say it once, a moment after launch, whatever the usage.
        if CommandLine.arguments.contains("--go-outside-preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.showBubble(preview: true) }
        }
    }

    // MARK: - Go outside

    /// Once a minute, on the minute, with Archimedes's turn in the cue. Its
    /// own timer rather than `MinuteCue`'s, which falls silent under Reduce
    /// Motion: the bubble still has something to say then, without the bounce.
    private func scheduleBubble() {
        bubbleTimer?.invalidate()
        let t = Timer(fire: MinuteCue.nextMinute(after: Date()), interval: 0, repeats: false) { [weak self] _ in
            self?.showBubble(preview: false)
            self?.scheduleBubble()
        }
        RunLoop.main.add(t, forMode: .common)
        bubbleTimer = t
    }

    private var previewing = false

    private func showBubble(preview: Bool) {
        guard appearance.style == .character, !bubble.isShowing else { return }
        guard preview || GoOutside.shouldShow(GoOutside.weekly(in: latest.limits.limits), now: Date()) else { return }
        guard let button = controller.button, let window = button.window, let screen = window.screen else { return }
        let slot = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard slot.width >= 8 else { return }   // stepped aside for a reveal: no owl to speak
        // Under his beak, which is the owl's bottom middle, at the bar's bottom
        // edge: the top of the visible frame (the button is shorter than the bar).
        let tip = NSPoint(x: slot.midX, y: min(slot.minY, screen.visibleFrame.maxY))
        previewing = preview
        bubble.show(text: GoOutside.text, tip: tip, on: screen)
    }

    /// The bubble was clicked: he shuts his eyes until the week resets.
    private func bubbleClicked() {
        guard !previewing, let weekly = GoOutside.weekly(in: latest.limits.limits) else { return }
        GoOutside.dismiss(weekly)
        App.log("go outside: clicked; eyes shut until \(weekly.resetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "?")")
        render(latest)
    }

    /// A one-line breadcrumb per poll. A menu-bar app has nowhere to print a
    /// diagnostic, and "no numbers" has several very different causes.
    static func log(_ message: String) {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ClaudeUsage.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(stamp)  \(message)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: path)
        }
    }

    // MARK: - Poll

    private func poll(force: Bool = false) {
        if force { forceNext = true }
        guard !pollInFlight else { pollPending = true; return }
        pollInFlight = true
        let forcing = forceNext
        forceNext = false

        pollQueue.async { [weak self] in
            guard self != nil else { return }
            var snapshot = Snapshot()
            let credentials = CredentialStore.result()
            snapshot.limits = UsageClient.snapshot(credentials: credentials, force: forcing)
            App.log("credential: " + (credentials.failureMessage ?? "ok")
                    + " | limits: \(snapshot.limits.limits.count)"
                    + " | status: \(snapshot.limits.statusText)")
            snapshot.sessions = SessionRegistry.load()
            snapshot.updatedAt = Date()

            DispatchQueue.main.async {
                guard let self else { return }
                self.latest = snapshot
                self.render(snapshot)
                // Rebuild under the user's cursor if the menu is still up.
                // Rebuilding re-seeds liveMenu/liveHeader, so the spinner state
                // is cleared on the view that replaces the spinning one.
                if let menu = self.liveMenu {
                    menu.removeAllItems()
                    self.buildMenu(menu)
                }
                self.liveHeader?.setRefreshing(false)
                self.pollInFlight = false
                if self.pollPending { self.pollPending = false; self.poll() }
            }
        }
    }

    private func render(_ snapshot: Snapshot) {
        // With no usable number, draw the CHOSEN meter empty and greyed rather
        // than substituting a different shape. Swapping in a dot made the
        // style picker look broken — every choice rendered identically —
        // and an unfilled meter already reads as "nothing to report" without
        // implying a full allowance.
        let session = snapshot.limits.limits.first
        let fraction = CGFloat(session?.fraction ?? 0)
        if appearance.style == .character {
            // The owl shows both windows at once. By default its eyelids droop
            // with the session — open at 0, shut at 100% — and the weekly
            // window is its health: the whites go bloodshot and the pupils run
            // green to red. With Settings ▸ One Eye per Window each eye is its
            // own window instead, the left the session and the right the week.
            // A blink closes whatever the lids have left open.
            let weekly = CGFloat(GoOutside.weekly(in: snapshot.limits.limits)?.fraction ?? 0)
            // Shut, and staying shut, after "go outside" was clicked this week.
            let closure = GoOutside.eyesShut(now: Date()) ? 1 : blinkClosure
            if MenuPreferences.eyePerWindow() {
                // A pair colours each eye by its window: session left, week right.
                let pupils = colors.map { (Self.color($0.sessionHex), Self.color($0.weeklyHex)) }
                controller.setIcon(CharacterIcon.owl(leftEye: fraction, rightEye: weekly, closure: closure, pupils: pupils))
            } else {
                // Both pupils carry the week here, so a pair gives both its weekly colour.
                let pupils = colors.map { (Self.color($0.weeklyHex), Self.color($0.weeklyHex)) }
                let lids = fraction + (1 - fraction) * closure
                controller.setIcon(CharacterIcon.owl(session: lids, weekly: weekly, pupils: pupils))
            }
            return
        }
        let color = session == nil ? NSColor.secondaryLabelColor
            : colors.map { Self.color($0.sessionHex) } ?? MeterColor.usage(fraction)
        controller.setIcon(MeterIcon.image(style: appearance.style, fraction: fraction, color: color))
    }

    // MARK: - Menu

    private func buildMenu(_ menu: NSMenu) {
        let snapshot = latest

        let plan = snapshot.limits.planLabel.isEmpty ? "Claude" : "Claude · " + snapshot.limits.planLabel
        let headerItem = NSMenuItem()
        let headerView = HeaderView(title: plan,
                                    age: RelativeTime.ago(snapshot.updatedAt)) { [weak self] in
            self?.poll(force: true)
        }
        headerItem.view = headerView
        menu.addItem(headerItem)
        liveMenu = menu
        liveHeader = headerView

        if !snapshot.limits.statusText.isEmpty {
            menu.addItem(disabled(snapshot.limits.statusText))
        }
        if snapshot.limits.limits.isEmpty && snapshot.limits.statusText.isEmpty {
            menu.addItem(disabled("No limit data"))
        }
        // Each bar wears the colour of its own fraction on the pupils' ramp,
        // #005401 reddening to #FF5401, so the weekly bar matches the pupils —
        // or, with a pair chosen, its window's colour: the first limit is the
        // session, the second the week.
        for (index, limit) in snapshot.limits.limits.enumerated() {
            let item = NSMenuItem()
            let color = colors.map { Self.color(index == 0 ? $0.sessionHex : $0.weeklyHex) }
                ?? MeterColor.health(CGFloat(limit.fraction))
            item.view = LimitBarView(limit: limit, color: color)
            menu.addItem(item)
        }

        if MenuPreferences.showSessions() {
            sessionItems(snapshot).forEach(menu.addItem)
        }

        let afterSessions = NSMenuItem.separator()
        afterSessions.tag = Self.afterSessionsTag
        menu.addItem(afterSessions)
        // Sign-in is offered whenever the credential is unusable. It runs the
        // same claude.ai authorisation Claude Code does, from here: the
        // browser opens on the consent page and comes back to the app, and
        // the app keeps the resulting login alive itself.
        if signingIn {
            menu.addItem(disabled("Waiting for claude.ai in the browser…"))
        } else if !snapshot.limits.statusText.isEmpty {
            menu.addItem(action("Sign In with Claude…", #selector(signIn)))
        }

        // Everything the user can set lives one level down, so the top level
        // is the numbers, a settings entry, and Quit.
        SettingsMenu.addFooter(to: menu, appName: "Claude Usage", items: { [unowned self] settings in
            // Keep-open checkbox: the sessions section appears or goes in the
            // menu behind it while Settings stays up.
            settings.addItem(ToggleMenuItem.make(title: "Show Sessions", isOn: MenuPreferences.showSessions()) { [weak self] on in
                self?.setShowSessions(on)
            })
            // Only the owl has eyes; the meters show the session either way.
            settings.addItem(ToggleMenuItem.make(title: "One Eye per Window", isOn: MenuPreferences.eyePerWindow()) { [weak self] on in
                MenuPreferences.setEyePerWindow(on)
                if let self { self.render(self.latest) }
            })
            // While the numbers are fine the sign-in lives down here: a login
            // of the app's own is what lets it stay signed in without the CLI.
            // Only a login this app made is its to forget; Claude Code's stays.
            var account: [NSMenuItem] = []
            if !self.signingIn {
                account.append(self.action(OwnLogin.exists ? "Sign In Again…" : "Sign In with Claude…", #selector(self.signIn)))
            }
            if OwnLogin.exists {
                account.append(self.action("Sign Out of Claude Usage", #selector(self.signOut)))
            }
            if !account.isEmpty {
                settings.addItem(.separator())
                account.forEach(settings.addItem)
            }
        }, belowSettings: { [unowned self] menu in
            // Icon and Color side by side in the main menu, right below
            // Settings, so the two pickers read as a pair.
            menu.addItem(self.appearanceMenu.menuItem())
            let color = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
            color.submenu = NSMenu(title: "Color")
            self.addColorPairs(to: color.submenu!)
            menu.addItem(color)
        })
    }

    // MARK: - Colour pairs

    private static func color(_ hex: String) -> NSColor { MeterColor.color(fromHex: hex) ?? .systemGray }

    /// The Color submenu: the usage ramp, then one row per pair with a two-dot
    /// swatch (session left, weekly right).
    private func addColorPairs(to menu: NSMenu) {
        let ramp = NSMenuItem(title: "Usage (Green → Red)", action: #selector(pickColorPair(_:)), keyEquivalent: "")
        ramp.target = self
        ramp.image = Self.swatch([MeterColor.health(0), MeterColor.health(1)])
        ramp.state = colors == nil ? .on : .off
        menu.addItem(ramp)
        for pair in ColorPair.presets {
            let item = NSMenuItem(title: pair.name, action: #selector(pickColorPair(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pair.id
            item.image = Self.swatch([Self.color(pair.sessionHex), Self.color(pair.weeklyHex)])
            item.state = pair == colors ? .on : .off
            menu.addItem(item)
        }
    }

    private static func swatch(_ colors: [NSColor], diameter: CGFloat = 12) -> NSImage {
        let gap: CGFloat = 3
        let image = NSImage(size: NSSize(width: diameter * 2 + gap, height: diameter), flipped: false) { _ in
            for (i, color) in colors.enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: CGFloat(i) * (diameter + gap), y: 0, width: diameter, height: diameter)).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    @objc private func pickColorPair(_ sender: NSMenuItem) {
        let id = sender.representedObject as? String
        colors = ColorPair.presets.first(where: { $0.id == id })
        ColorPair.save(colors)
        render(latest)
    }

    // MARK: - Menu item helpers

    private func header(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)]
        )
        item.isEnabled = false
        return item
    }

    private func disabled(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Actions

    /// Tags for the sessions section's rows and the separator after it, so the
    /// section can be added or removed in place while the menu is up.
    private static let sessionsTag = 0x5E55
    private static let afterSessionsTag = 0x5E56

    /// The sessions section: a separator, a header, one row per session.
    private func sessionItems(_ snapshot: Snapshot) -> [NSMenuItem] {
        let busy = snapshot.sessions.filter(\.isBusy).count
        var items: [NSMenuItem] = [.separator(), header("Sessions   \(snapshot.sessions.count) running, \(busy) busy")]
        for session in snapshot.sessions.prefix(12) {
            items.append(disabled("\(session.isBusy ? "●" : "○") \(session.name)   \(session.status)"))
        }
        items.forEach { $0.tag = Self.sessionsTag }
        return items
    }

    /// Shows or hides the sessions section. If the menu is still up, the rows
    /// appear or go in place — not a rebuild, which would pull the Settings
    /// submenu (where the checkbox is) out from under the cursor.
    private func setShowSessions(_ on: Bool) {
        MenuPreferences.setShowSessions(on)
        guard let menu = liveMenu else { return }
        for item in menu.items where item.tag == Self.sessionsTag { menu.removeItem(item) }
        let snapshot = latest
        guard on,
              let anchor = menu.items.firstIndex(where: { $0.tag == Self.afterSessionsTag }) else { return }
        for (offset, item) in sessionItems(snapshot).enumerated() {
            menu.insertItem(item, at: anchor + offset)
        }
    }

    // MARK: - Sign-in

    private let signInFlow = SignIn()
    private var signingIn = false

    /// Open claude.ai's consent page and wait for it to come back. The
    /// menu says so meanwhile, and a finished sign-in refreshes the numbers
    /// straight away rather than on the next poll.
    @objc private func signIn() {
        do {
            let url = try signInFlow.start { [weak self] outcome in
                DispatchQueue.main.async { self?.signInEnded(outcome) }
            }
            signingIn = true
            App.log("sign-in: waiting for the browser")
            NSWorkspace.shared.open(url)
        } catch {
            App.log("sign-in: could not listen on localhost: \(error)")
            let alert = NSAlert()
            alert.messageText = "Could not start the sign-in"
            alert.informativeText = "The app could not open a local port for claude.ai to come back to. Try again in a moment."
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        if let menu = liveMenu {
            menu.removeAllItems()
            buildMenu(menu)
        }
    }

    private func signInEnded(_ outcome: SignIn.Outcome) {
        signingIn = false
        switch outcome {
        case .signedIn(let plan):
            App.log("sign-in: done (\(plan))")
            poll(force: true)
        case .denied(let reason):
            App.log("sign-in: denied (\(reason))")
        case .failed(let reason):
            App.log("sign-in: failed — \(reason)")
            let alert = NSAlert()
            alert.messageText = "Sign-in did not complete"
            alert.informativeText = reason + "."
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        case .timedOut:
            App.log("sign-in: timed out")
        }
        if let menu = liveMenu {
            menu.removeAllItems()
            buildMenu(menu)
        }
    }

    @objc private func signOut() {
        OwnLogin.forget()
        CredentialStore.invalidate()
        App.log("sign-out: own login forgotten")
        poll(force: true)
    }

}

// `install.sh` registers Start-at-Login by running this binary, because
// SMAppService can only ever register the calling process's own bundle. Handle
// it and exit before the status item is created — otherwise the installer
// would leave a second, headless menu-bar instance running.
// Shared with every other app in the suite (StatusItemKit). The hand-rolled
// version this replaced read any value other than "off" as on, so `--login
// status` — a query — silently registered the app, and a typo like `--login yes`
// did too.
LoginCLI.runIfRequested()

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
