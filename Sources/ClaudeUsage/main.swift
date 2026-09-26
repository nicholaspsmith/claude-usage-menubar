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
    /// stops work — while the owl shows both windows at once.
    /// There is no colour to choose: every colour is `MeterColor.usage` of a
    /// fraction, cyan when a window is fresh and red when it is spent, so the
    /// owl's pupils and the menu's bars say the same thing.
    private let appearance = MeterAppearance(defaultStyle: .character)
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
            // The owl shows both windows at once. Its eyelids droop with the
            // session — open at 0, shut at 100% — and the weekly window is its
            // health: the whites go bloodshot and the pupils run cyan to red.
            let weekly = snapshot.limits.limits.dropFirst().first
            controller.setIcon(CharacterIcon.owl(session: fraction, weekly: CGFloat(weekly?.fraction ?? 0)))
            return
        }
        let color = session == nil ? NSColor.secondaryLabelColor : MeterColor.usage(fraction)
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
        // Each bar wears the colour of its own fraction, the same ramp as the
        // owl's pupils, so the weekly bar and the pupils always agree.
        for limit in snapshot.limits.limits {
            let item = NSMenuItem()
            item.view = LimitBarView(limit: limit, color: MeterColor.usage(CGFloat(limit.fraction)))
            menu.addItem(item)
        }

        if MenuPreferences.showSessions() {
            menu.addItem(.separator())
            let busy = snapshot.sessions.filter(\.isBusy).count
            menu.addItem(header("Sessions   \(snapshot.sessions.count) running, \(busy) busy"))
            for session in snapshot.sessions.prefix(12) {
                menu.addItem(disabled("\(session.isBusy ? "●" : "○") \(session.name)   \(session.status)"))
            }
        }

        menu.addItem(.separator())
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
        let settings = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        settingsMenu.addItem(appearanceMenu.menuItem())
        let sessions = action("Show Sessions", #selector(toggleSessions))
        sessions.state = MenuPreferences.showSessions() ? .on : .off
        settingsMenu.addItem(sessions)
        let login = action("Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        settingsMenu.addItem(login)
        // While the numbers are fine the sign-in lives down here: a login of
        // the app's own is what lets it stay signed in without the CLI. Only
        // a login this app made is its to forget; Claude Code's stays.
        settingsMenu.addItem(.separator())
        if !signingIn {
            settingsMenu.addItem(action(OwnLogin.exists ? "Sign In Again…" : "Sign In with Claude…", #selector(signIn)))
        }
        if OwnLogin.exists {
            settingsMenu.addItem(action("Sign Out of Claude Usage", #selector(signOut)))
        }
        settings.submenu = settingsMenu
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(AppVersion.menuItem())
        menu.addItem(action("Quit", #selector(quit)))
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

    @objc private func toggleLogin() { LoginItem.toggle() }

    /// Flips the sessions section and rebuilds the menu under the cursor if
    /// it is still up, so the rows appear or go without reopening it.
    @objc private func toggleSessions() {
        MenuPreferences.setShowSessions(!MenuPreferences.showSessions())
        if let menu = liveMenu {
            menu.removeAllItems()
            buildMenu(menu)
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

    @objc private func quit() { NSApp.terminate(nil) }
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
