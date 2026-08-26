import AppKit
import ClaudeUsageCore
import StatusItemKit

/// Everything one poll produces. Held whole so the menu renders a single
/// consistent moment rather than a mix of two polls.
private struct Snapshot {
    var limits = LimitsSnapshot()
    var daily: [DailyUsage] = []
    var sessions: [ClaudeSession] = []
}

final class App: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController!
    /// Steps aside while Curtain reveals its hidden block — the bar has no
    /// spare room, and a reveal borrows slots from apps that cooperate.
    private var yieldClient: YieldClient!
    private var latest = Snapshot()

    /// The window that decides the icon. The five-hour session limit is the one
    /// that actually stops work, so it is what the meter shows; the weekly
    /// figure lives in the menu.
    private static let warnPct = 80

    /// Estimated cost is off by default.
    ///
    /// On a subscription without overage billing enabled, the dollar figure is
    /// money that cannot be charged — the tokens are covered by the flat fee,
    /// and going over the limit stops work rather than billing for it. Showing
    /// it by default invites reading a number that will never appear on a bill.
    /// It stays available for anyone on API billing, or as a sense of scale.
    /// Which meter shape draws the icon. Always fed the session fraction —
    /// the weekly window is the slower, less urgent one, so it lives in the
    /// menu rather than competing for the single glyph.
    private var meterStyle: MeterStyle {
        get { MeterStyle.from(UserDefaults.standard.string(forKey: MeterStyle.defaultsKey)) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: MeterStyle.defaultsKey) }
    }

    private var showsCost: Bool {
        get { UserDefaults.standard.bool(forKey: "ShowEstimatedCost") }
        set { UserDefaults.standard.set(newValue, forKey: "ShowEstimatedCost") }
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
            snapshot.daily = TranscriptStats.scan()
            snapshot.sessions = SessionRegistry.load()

            DispatchQueue.main.async {
                guard let self else { return }
                self.latest = snapshot
                self.render(snapshot)
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
        let color: NSColor
        if let session {
            let pct = Int((session.fraction * 100).rounded())
            color = Severity.level(pct: pct, warnPct: Self.warnPct).color
        } else {
            color = .secondaryLabelColor
        }
        switch meterStyle {
        case .arc:   controller.setIcon(MeterIcon.arc(fraction: fraction, color: color))
        case .gauge: controller.setIcon(MeterIcon.gauge(fraction: fraction, color: color))
        case .pie:   controller.setIcon(MeterIcon.pie(fraction: fraction, color: color))
        case .wedge: controller.setIcon(MeterIcon.wedge(fraction: fraction, color: color))
        }
    }

    // MARK: - Menu

    private func buildMenu(_ menu: NSMenu) {
        let snapshot = latest

        let plan = snapshot.limits.planLabel.isEmpty ? "Claude" : "Claude · " + snapshot.limits.planLabel
        menu.addItem(header(plan))

        if !snapshot.limits.statusText.isEmpty {
            menu.addItem(disabled(snapshot.limits.statusText))
        }
        if snapshot.limits.limits.isEmpty && snapshot.limits.statusText.isEmpty {
            menu.addItem(disabled("No limit data"))
        }
        for limit in snapshot.limits.limits {
            let item = NSMenuItem()
            item.view = LimitBarView(limit: limit, warnPct: Self.warnPct)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(header("Tokens"))
        let recent = snapshot.daily.suffix(7)
        if recent.isEmpty {
            menu.addItem(disabled("No recorded usage this week"))
        } else {
            for day in recent {
                var row = "\(day.day)   \(compact(day.total.total))"
                if showsCost {
                    let (dollars, complete) = day.cost()
                    row += "   " + money(dollars) + (complete ? "" : "+")
                }
                menu.addItem(disabled(row))
            }
            if let today = recent.last {
                menu.addItem(.separator())
                menu.addItem(header("Today by model"))
                for (model, usage) in today.byModel.sorted(by: { $0.value.total > $1.value.total }) {
                    menu.addItem(disabled("\(short(model))   \(compact(usage.total))"))
                }
            }
        }

        menu.addItem(.separator())
        let busy = snapshot.sessions.filter(\.isBusy).count
        menu.addItem(header("Sessions   \(snapshot.sessions.count) running, \(busy) busy"))
        for session in snapshot.sessions.prefix(12) {
            menu.addItem(disabled("\(session.isBusy ? "●" : "○") \(session.name)   \(session.status)"))
        }

        menu.addItem(.separator())
        menu.addItem(action("Refresh Now", #selector(refresh)))
        // Re-auth is offered whenever the credential is unusable. Only the CLI
        // can mint a token, and its login is an interactive browser flow, so
        // this hands off to a Terminal window rather than pretending the menu
        // bar can complete it.
        if !snapshot.limits.statusText.isEmpty {
            menu.addItem(action("Sign In to Claude Code…", #selector(signIn)))
        }

        let iconItem = NSMenuItem(title: "Icon", action: nil, keyEquivalent: "")
        let iconMenu = NSMenu()
        for style in MeterStyle.allCases {
            let choice = NSMenuItem(title: style.title, action: #selector(pickStyle(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = style.rawValue
            choice.state = style == meterStyle ? .on : .off
            iconMenu.addItem(choice)
        }
        iconItem.submenu = iconMenu
        menu.addItem(iconItem)

        let cost = action("Show Estimated Cost", #selector(toggleCost))
        cost.state = showsCost ? .on : .off
        cost.toolTip = "API list price for these tokens. On a subscription without overage billing this is not a bill — it is only a sense of scale."
        menu.addItem(cost)
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

    private func compact(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return String(format: "%.0fK", Double(tokens) / 1_000) }
        return "\(tokens)"
    }

    private func money(_ dollars: Double) -> String {
        dollars >= 100 ? String(format: "$%.0f", dollars) : String(format: "$%.2f", dollars)
    }

    /// "claude-opus-5" reads better as "opus-5" in a narrow menu.
    private func short(_ model: String) -> String {
        model.hasPrefix("claude-") ? String(model.dropFirst("claude-".count)) : model
    }

    // MARK: - Actions

    @objc private func refresh() { poll(force: true) }
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
    @objc private func toggleCost() { showsCost.toggle() }

    @objc private func pickStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        meterStyle = MeterStyle.from(raw)
        // Repaint from the snapshot in hand rather than waiting up to a minute
        // for the next poll to make the choice visible.
        render(latest)
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
