import Foundation

/// Published per-million-token rates, used to turn recorded token counts into
/// an estimated spend.
///
/// These are Anthropic's first-party API list prices. They are the wrong
/// number for a Pro/Max subscription — a subscription is a flat fee and these
/// tokens cost nothing extra — so treat the result as "what this would have
/// cost on the API", which is what makes it a useful sense of scale. Bedrock
/// and Vertex are partner-priced and not covered here.
public struct ModelPrice: Equatable {
    public let inputPerMTok: Double
    public let outputPerMTok: Double

    /// Cache reads bill at a tenth of the base input rate.
    public var cacheReadPerMTok: Double { inputPerMTok * 0.1 }
    /// Cache writes carry a 1.25x premium at the default five-minute TTL.
    /// A one-hour TTL doubles it instead, but the transcripts don't record
    /// which TTL was used, so the common case is assumed.
    public var cacheWritePerMTok: Double { inputPerMTok * 1.25 }

    public init(inputPerMTok: Double, outputPerMTok: Double) {
        self.inputPerMTok = inputPerMTok
        self.outputPerMTok = outputPerMTok
    }
}

public enum Pricing {
    /// Longest-prefix wins, so `claude-opus-4-8` is not matched by the
    /// `claude-opus-4` family before its own entry is considered.
    static let table: [(prefix: String, price: ModelPrice)] = [
        ("claude-fable-5",   ModelPrice(inputPerMTok: 10, outputPerMTok: 50)),
        ("claude-mythos-5",  ModelPrice(inputPerMTok: 10, outputPerMTok: 50)),
        ("claude-opus-5",    ModelPrice(inputPerMTok: 5,  outputPerMTok: 25)),
        ("claude-opus-4-8",  ModelPrice(inputPerMTok: 5,  outputPerMTok: 25)),
        ("claude-opus-4-7",  ModelPrice(inputPerMTok: 5,  outputPerMTok: 25)),
        ("claude-opus-4-6",  ModelPrice(inputPerMTok: 5,  outputPerMTok: 25)),
        ("claude-sonnet-5",  ModelPrice(inputPerMTok: 2,  outputPerMTok: 10)),
        ("claude-sonnet-4-6", ModelPrice(inputPerMTok: 3, outputPerMTok: 15)),
        ("claude-haiku-4-5", ModelPrice(inputPerMTok: 1,  outputPerMTok: 5)),
    ]

    /// The rate card for a model id, or nil when the id is unrecognised.
    ///
    /// Unknown returns nil rather than a default: a model released after this
    /// table was written would otherwise be silently priced as something it
    /// isn't, and a visibly missing cost is easier to notice than a wrong one.
    public static func price(for model: String) -> ModelPrice? {
        let id = model.lowercased()
        // Claude Code decorates ids with a context suffix ("opus[1m]"), and
        // the API returns pinned dated snapshots. Both should match the family.
        let normalized = id.replacingOccurrences(of: "[1m]", with: "")
        return table
            .filter { normalized.hasPrefix($0.prefix) || normalized.contains($0.prefix) }
            .max { $0.prefix.count < $1.prefix.count }?
            .price
    }

    /// Estimated dollar cost of one usage record.
    public static func cost(model: String, usage: TokenUsage) -> Double? {
        guard let price = price(for: model) else { return nil }
        let million = 1_000_000.0
        return Double(usage.input) / million * price.inputPerMTok
            + Double(usage.output) / million * price.outputPerMTok
            + Double(usage.cacheRead) / million * price.cacheReadPerMTok
            + Double(usage.cacheWrite) / million * price.cacheWritePerMTok
    }
}
