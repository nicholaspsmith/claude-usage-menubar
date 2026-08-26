import Foundation

/// One live Claude Code session, as the CLI advertises it on this machine.
public struct ClaudeSession: Equatable {
    public let pid: Int
    public let name: String
    public let cwd: String
    public let kind: String     // "interactive", "bg", ...
    public let status: String   // "busy", "idle", ...

    public init(pid: Int, name: String, cwd: String, kind: String, status: String) {
        self.pid = pid
        self.name = name
        self.cwd = cwd
        self.kind = kind
        self.status = status
    }

    public var isBusy: Bool { status.lowercased() == "busy" }
    public var project: String { (cwd as NSString).lastPathComponent }
}

public enum SessionRegistry {
    /// Claude Code writes one file per session, named for the pid.
    public static func directory() -> String {
        let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path
        return dir + "/sessions"
    }

    public static func load(directory: String = SessionRegistry.directory(),
                            isAlive: (Int) -> Bool = SessionRegistry.processExists) -> [ClaudeSession] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory) else { return [] }
        return names
            .filter { $0.hasSuffix(".json") }
            .compactMap { name -> ClaudeSession? in
                guard let data = fm.contents(atPath: directory + "/" + name) else { return nil }
                return parse(data)
            }
            // A session file outlives a crashed CLI, so the pid is the only
            // honest liveness signal — a stale row would report work that
            // stopped hours ago as still running.
            .filter { isAlive($0.pid) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func parse(_ data: Data) -> ClaudeSession? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let pid = json["pid"] as? Int
        else { return nil }
        let cwd = json["cwd"] as? String ?? ""
        return ClaudeSession(
            pid: pid,
            name: json["name"] as? String ?? (cwd as NSString).lastPathComponent,
            cwd: cwd,
            kind: json["kind"] as? String ?? "",
            status: json["status"] as? String ?? ""
        )
    }

    /// Signal 0 tests for existence without delivering anything.
    public static func processExists(_ pid: Int) -> Bool {
        kill(pid_t(pid), 0) == 0 || errno == EPERM
    }
}
