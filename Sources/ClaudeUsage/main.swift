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
            snapshot.limits = UsageClient.snapshot(credentials: CredentialStore.load(), force: forcing)
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
        guard let session = snapshot.limits.limits.first else {
            // No usable number is not the same as zero used. A dot says
            // "nothing to report" without implying a full allowance.
            controller.setIcon(MeterIcon.dot(color: .secondaryLabelColor))
            return
        }
        let pct = Int((session.fraction * 100).rounded())
        let severity = Severity.level(pct: pct, warnPct: Self.warnPct)
        controller.setIcon(MeterIcon.arc(fraction: session.fraction, color: severity.color))
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
            let pct = Int((limit.fraction * 100).rounded())
            menu.addItem(disabled("\(limit.label)   \(pct)%\(resetSuffix(limit))"))
        }

        menu.addItem(.separator())
        menu.addItem(header("Tokens"))
        let recent = snapshot.daily.suffix(7)
        if recent.isEmpty {
            menu.addItem(disabled("No recorded usage this week"))
        } else {
            for day in recent {
                let (dollars, complete) = day.cost()
                let money = complete ? money(dollars) : money(dollars) + "+"
                menu.addItem(disabled("\(day.day)   \(compact(day.total.total))   \(money)"))
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

    private func resetSuffix(_ limit: UsageLimit) -> String {
        guard let resets = limit.resetsAt else { return "" }
        let remaining = resets.timeIntervalSinceNow
        guard remaining > 0 else { return "" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        return hours > 0 ? "   resets in \(hours)h \(minutes)m" : "   resets in \(minutes)m"
    }

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
