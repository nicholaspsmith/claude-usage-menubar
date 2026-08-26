import Foundation

/// Token totals for one calendar day, split by model.
public struct DailyUsage: Equatable {
    public let day: String              // yyyy-MM-dd, local time
    public var byModel: [String: TokenUsage]

    public init(day: String, byModel: [String: TokenUsage] = [:]) {
        self.day = day
        self.byModel = byModel
    }

    public var total: TokenUsage { byModel.values.reduce(TokenUsage(), +) }

    /// Estimated spend, and whether every model in the day was priceable.
    /// A day containing an unknown model reports `complete: false` so the UI
    /// can mark the figure as a floor rather than quietly under-reporting.
    public func cost() -> (dollars: Double, complete: Bool) {
        var total = 0.0
        var complete = true
        for (model, usage) in byModel {
            if let c = Pricing.cost(model: model, usage: usage) { total += c } else { complete = false }
        }
        return (total, complete)
    }
}

public enum TranscriptStats {
    public static func projectsDirectory() -> String {
        let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path
        return dir + "/projects"
    }

    /// Aggregate the last `days` days of transcripts.
    ///
    /// Transcripts are append-only JSONL and there are a great many of them, so
    /// files untouched within the window are skipped on mtime before being
    /// opened. This is a full re-scan each time rather than an incremental
    /// tail: it keeps the result correct when old files are edited or removed,
    /// and the window keeps the cost bounded.
    public static func scan(directory: String = TranscriptStats.projectsDirectory(),
                            days: Int = 7,
                            now: Date = Date()) -> [DailyUsage] {
        let fm = FileManager.default
        let cutoff = Calendar.current.startOfDay(for: now.addingTimeInterval(-Double(days - 1) * 86_400))
        var byDay: [String: DailyUsage] = [:]

        guard let walker = fm.enumerator(atPath: directory) else { return [] }
        for case let relative as String in walker {
            guard relative.hasSuffix(".jsonl") else { continue }
            let path = directory + "/" + relative
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let modified = attrs[.modificationDate] as? Date,
               modified < cutoff { continue }
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let record = parse(line: line, cutoff: cutoff) else { continue }
                byDay[record.day, default: DailyUsage(day: record.day)]
                    .byModel[record.model, default: TokenUsage()] += record.usage
            }
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    struct Record { let day: String; let model: String; let usage: TokenUsage }

    static func parse(line: Substring, cutoff: Date) -> Record? {
        guard let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let model = message["model"] as? String,
              let usageJSON = message["usage"] as? [String: Any],
              let usage = TokenUsage(json: usageJSON),
              let stamp = json["timestamp"] as? String,
              let date = isoDate(stamp), date >= cutoff
        else { return nil }
        return Record(day: dayFormatter.string(from: date), model: model, usage: usage)
    }

    static func isoDate(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    /// Days are bucketed in local time so "today" matches the user's day, not UTC's.
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
