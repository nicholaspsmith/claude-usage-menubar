// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// The numbers the menu shows, written to disk after every poll for anything
/// that cannot open the menu: shell scripts, Claude Code agents, launchd jobs.
///
/// `~/Library/Application Support/ClaudeUsage/usage.json`:
///
///     {
///       "schema": 1,
///       "updatedAt": "2026-11-10T04:00:00Z",
///       "plan": "Max 5x",
///       "status": "",                       // non-empty when the numbers are missing or stale, and why
///       "limits": [
///         { "window": "session", "label": "Session (5-hour)", "percent": 93, "fraction": 0.93,
///           "resetsAt": "2026-11-10T05:00:00Z", "resetsInSeconds": 3600 },
///         { "window": "weekly",  "label": "Weekly (7-day)",   "percent": 29, "fraction": 0.29,
///           "resetsAt": "2026-11-14T04:00:00Z", "resetsInSeconds": 345600 }
///       ]
///     }
///
/// The write is atomic, so a reader never sees a half-written file. It is
/// plain JSON and nothing in it is a secret: no token, no account.
public enum UsageExport {
    public static let schema = 1

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeUsage/usage.json")
    }

    /// `session` for the five-hour window, `weekly` for the seven-day one.
    static func window(for label: String) -> String {
        if label == UsageLimit.sessionLabel || label.lowercased().contains("session") { return "session" }
        if label == UsageLimit.weeklyLabel || label.lowercased().contains("week") { return "weekly" }
        return "other"
    }

    public static func payload(_ snapshot: LimitsSnapshot, updatedAt: Date) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return [
            "schema": schema,
            "updatedAt": iso.string(from: updatedAt),
            "plan": snapshot.planLabel,
            "status": snapshot.statusText,
            "limits": snapshot.limits.map { limit -> [String: Any] in
                [
                    "window": window(for: limit.label),
                    "label": limit.label,
                    "percent": Int((limit.fraction * 100).rounded()),
                    "fraction": limit.fraction,
                    "resetsAt": limit.resetsAt.map { iso.string(from: $0) } ?? NSNull(),
                    "resetsInSeconds": limit.resetsAt.map { Int($0.timeIntervalSince(updatedAt).rounded()) } ?? NSNull(),
                ]
            },
        ]
    }

    /// Writes the snapshot; failures are swallowed (a full disk must not take the menu down).
    public static func write(_ snapshot: LimitsSnapshot, updatedAt: Date = Date(), to url: URL = defaultURL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: payload(snapshot, updatedAt: updatedAt), options: [.sortedKeys, .prettyPrinted]) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// The last written file, for `ClaudeUsage --usage`.
    public static func readLatest(from url: URL = defaultURL) -> Data? {
        FileManager.default.contents(atPath: url.path)
    }
}
