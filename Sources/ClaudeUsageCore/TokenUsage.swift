import Foundation

/// The four token counters Claude Code records on every assistant message.
///
/// Cache reads and writes are tracked apart from plain input because they bill
/// at very different rates — a tenth and 1.25x of base input respectively — so
/// collapsing them into one "input" figure would make the cost estimate wrong
/// by an order of magnitude on a cache-heavy session.
public struct TokenUsage: Equatable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    public var total: Int { input + output + cacheRead + cacheWrite }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(input: lhs.input + rhs.input,
                   output: lhs.output + rhs.output,
                   cacheRead: lhs.cacheRead + rhs.cacheRead,
                   cacheWrite: lhs.cacheWrite + rhs.cacheWrite)
    }

    public static func += (lhs: inout TokenUsage, rhs: TokenUsage) { lhs = lhs + rhs }

    /// Both spellings appear in the wild: the API's snake_case and Claude
    /// Code's camelCase re-serialisation of the same record.
    public init?(json: [String: Any]) {
        func count(_ snake: String, _ camel: String) -> Int {
            if let n = json[snake] as? Int { return n }
            if let n = json[camel] as? Int { return n }
            if let d = json[snake] as? Double { return Int(d) }
            if let d = json[camel] as? Double { return Int(d) }
            return 0
        }
        self.init(input: count("input_tokens", "inputTokens"),
                  output: count("output_tokens", "outputTokens"),
                  cacheRead: count("cache_read_input_tokens", "cacheReadInputTokens"),
                  cacheWrite: count("cache_creation_input_tokens", "cacheCreationInputTokens"))
        if total == 0 { return nil }
    }
}
