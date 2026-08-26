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

    /// The window that decides the icon. The five-hour session limit is the one
    /// that actually stops work, so it is what the meter shows; the weekly
    /// figure lives in the menu.
    private static let warnPct = 80

    /// Shape and resting colour, both user-chosen, from StatusItemKit. Always
    /// fed the session fraction — the weekly window is the slower, less urgent
    /// one, so it lives in the menu rather than competing for the single glyph.
    private let appearance = MeterAppearance(defaultStyle: .arc,
                                             defaultColor: UsageColor.defaultResting)
    private lazy var appearanceMenu = AppearanceMenu(appearance: appearance) { [weak self] in
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
        let color = session.map {
            UsageColor.fill(fraction: $0.fraction, warnPct: Self.warnPct, resting: appearance.color)
        } ?? .secondaryLabelColor
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
        for limit in snapshot.limits.limits {
            let item = NSMenuItem()
            item.view = LimitBarView(limit: limit, warnPct: Self.warnPct, resting: appearance.color)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let busy = snapshot.sessions.filter(\.isBusy).count
        menu.addItem(header("Sessions   \(snapshot.sessions.count) running, \(busy) busy"))
        for session in snapshot.sessions.prefix(12) {
            menu.addItem(disabled("\(session.isBusy ? "●" : "○") \(session.name)   \(session.status)"))
        }

        menu.addItem(.separator())
        // Re-auth is offered whenever the credential is unusable. Only the CLI
        // can mint a token, and its login is an interactive browser flow, so
        // this hands off to a Terminal window rather than pretending the menu
        // bar can complete it.
        if !snapshot.limits.statusText.isEmpty {
            menu.addItem(action("Sign In to Claude Code…", #selector(signIn)))
        }

        menu.addItem(appearanceMenu.menuItem())

        let login = action("Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
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

    // MARK: - Formatting




    // MARK: - Actions

    @objc private func toggleLogin() { LoginItem.toggle() }

    @objc private func signIn() {
        // `claude auth login` opens a browser and waits, so it needs a real
        // terminal to live in. Refresh shortly after so a completed sign-in
        // shows up without waiting for the regular poll.
        let script = """
        tell application "Terminal"
            activate
            do script "claude auth login"
        end tell
        """
        if let osa = NSAppleScript(source: script) {
            var error: NSDictionary?
            osa.executeAndReturnError(&error)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.poll(force: true) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

// `install.sh` registers Start-at-Login by running this binary, because
// SMAppService can only ever register the calling process's own bundle. Handle
// it and exit before the status item is created — otherwise the installer
// would leave a second, headless menu-bar instance running.
if let flag = CommandLine.arguments.firstIndex(of: "--login") {
    let on = CommandLine.arguments.count > flag + 1 ? CommandLine.arguments[flag + 1] != "off" : true
    do {
        try LoginItem.setEnabled(on)
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("login item: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
