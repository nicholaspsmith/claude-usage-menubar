import XCTest
@testable import ClaudeUsageCore

final class PricingTests: XCTestCase {

    func testKnownModelsPriced() {
        XCTAssertEqual(Pricing.price(for: "claude-opus-5")?.inputPerMTok, 5)
        XCTAssertEqual(Pricing.price(for: "claude-sonnet-5")?.outputPerMTok, 10)
        XCTAssertEqual(Pricing.price(for: "claude-haiku-4-5-20251001")?.inputPerMTok, 1)
    }

    // Claude Code decorates the id with a context suffix; it is the same model.
    func testContextSuffixStripped() {
        XCTAssertEqual(Pricing.price(for: "claude-opus-5[1m]")?.inputPerMTok, 5)
    }

    // The longest matching prefix must win, or claude-opus-4-8 would be priced
    // by whichever opus entry happened to be scanned first.
    func testLongestPrefixWins() {
        XCTAssertEqual(Pricing.price(for: "claude-opus-4-8")?.inputPerMTok, 5)
        XCTAssertEqual(Pricing.price(for: "claude-sonnet-4-6")?.outputPerMTok, 15)
    }

    // A model released after this table was written must be visibly missing,
    // never silently priced as something else.
    func testUnknownModelIsNil() {
        XCTAssertNil(Pricing.price(for: "claude-nextthing-9"))
        XCTAssertNil(Pricing.cost(model: "gpt-4", usage: TokenUsage(input: 1000)))
    }

    // Cache traffic bills at 0.1x read / 1.25x write of base input. Collapsing
    // it into plain input would be wrong by an order of magnitude.
    func testCacheRatesDerivedFromInput() {
        let opus = Pricing.price(for: "claude-opus-5")!
        XCTAssertEqual(opus.cacheReadPerMTok, 0.5, accuracy: 0.0001)
        XCTAssertEqual(opus.cacheWritePerMTok, 6.25, accuracy: 0.0001)
    }

    func testCostSumsAllFourCounters() {
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000, cacheWrite: 1_000_000)
        // 5 + 25 + 0.5 + 6.25
        XCTAssertEqual(Pricing.cost(model: "claude-opus-5", usage: usage)!, 36.75, accuracy: 0.0001)
    }

    // A day containing an unpriceable model reports its cost as a floor.
    func testDailyCostFlagsIncompletePricing() {
        var day = DailyUsage(day: "2026-08-25")
        day.byModel["claude-opus-5"] = TokenUsage(input: 1_000_000)
        day.byModel["claude-unknown-7"] = TokenUsage(input: 1_000_000)
        let (dollars, complete) = day.cost()
        XCTAssertEqual(dollars, 5.0, accuracy: 0.0001)
        XCTAssertFalse(complete)
    }
}

final class TokenUsageTests: XCTestCase {

    func testAcceptsSnakeAndCamelSpellings() {
        let snake = TokenUsage(json: ["input_tokens": 10, "output_tokens": 5,
                                      "cache_read_input_tokens": 3, "cache_creation_input_tokens": 2])
        let camel = TokenUsage(json: ["inputTokens": 10, "outputTokens": 5,
                                      "cacheReadInputTokens": 3, "cacheCreationInputTokens": 2])
        XCTAssertEqual(snake, camel)
        XCTAssertEqual(snake?.total, 20)
    }

    // A record with no tokens carries no information and must not create an
    // empty per-model row in the day's breakdown.
    func testAllZeroIsNil() {
        XCTAssertNil(TokenUsage(json: ["input_tokens": 0]))
        XCTAssertNil(TokenUsage(json: [:]))
    }

    func testAdditionIsComponentwise() {
        let a = TokenUsage(input: 1, output: 2, cacheRead: 3, cacheWrite: 4)
        XCTAssertEqual(a + a, TokenUsage(input: 2, output: 4, cacheRead: 6, cacheWrite: 8))
    }
}

final class CredentialPlanLabelTests: XCTestCase {

    func testMaxTierParsesMultiplier() {
        XCTAssertEqual(CredentialStore.planLabel(tier: "max_20x", subscription: "max"), "Max 20x")
        XCTAssertEqual(CredentialStore.planLabel(tier: "MAX_5X", subscription: ""), "Max 5X")
    }

    // The real tier string is prefixed, so the multiplier has to be found
    // inside it rather than anchored at the start.
    func testRealWorldTierString() {
        XCTAssertEqual(CredentialStore.planLabel(tier: "default_claude_max_5x", subscription: "max"), "Max 5x")
        XCTAssertEqual(CredentialStore.planLabel(tier: "default_claude_max_20x", subscription: "max"), "Max 20x")
    }

    func testFallsBackToSubscriptionType() {
        XCTAssertEqual(CredentialStore.planLabel(tier: "", subscription: "pro"), "Pro")
        XCTAssertEqual(CredentialStore.planLabel(tier: "", subscription: ""), "")
    }
}

final class CredentialSelectionTests: XCTestCase {
    private func blob(sub: String, expiresAt: Double) -> Data {
        let json: [String: Any] = ["claudeAiOauth": [
            "accessToken": "tok-" + sub, "expiresAt": expiresAt, "subscriptionType": sub,
        ]]
        return try! JSONSerialization.data(withJSONObject: json)
    }
    private var future: Double { Date().addingTimeInterval(86_400).timeIntervalSince1970 * 1000 }
    private var past: Double { Date().addingTimeInterval(-86_400).timeIntervalSince1970 * 1000 }

    // The Keychain can hold several items under one service: an old sign-in
    // leaves its item behind when a new one is written. Asking for a single
    // match returns an arbitrary one, which is how an expired Pro token got
    // reported for a signed-in Max account.
    func testValidLoginBeatsExpiredOne() throws {
        let picked = try XCTUnwrap(CredentialStore.bestCredential(
            among: [blob(sub: "pro", expiresAt: past), blob(sub: "max", expiresAt: future)]))
        let oauth = ((try! JSONSerialization.jsonObject(with: picked)) as! [String: Any])["claudeAiOauth"] as! [String: Any]
        XCTAssertEqual(oauth["subscriptionType"] as? String, "max")
    }

    // Order must not decide it — the fossil came first on the real machine.
    func testOrderIndependent() throws {
        let picked = try XCTUnwrap(CredentialStore.bestCredential(
            among: [blob(sub: "max", expiresAt: future), blob(sub: "pro", expiresAt: past)]))
        let oauth = ((try! JSONSerialization.jsonObject(with: picked)) as! [String: Any])["claudeAiOauth"] as! [String: Any]
        XCTAssertEqual(oauth["subscriptionType"] as? String, "max")
    }

    // All lapsed: still return the furthest-dated, so the menu can say
    // "expired" against the most recent login rather than an ancient one.
    func testAllExpiredPicksLatest() throws {
        let older = Date().addingTimeInterval(-200_000).timeIntervalSince1970 * 1000
        let picked = try XCTUnwrap(CredentialStore.bestCredential(
            among: [blob(sub: "old", expiresAt: older), blob(sub: "recent", expiresAt: past)]))
        let oauth = ((try! JSONSerialization.jsonObject(with: picked)) as! [String: Any])["claudeAiOauth"] as! [String: Any]
        XCTAssertEqual(oauth["subscriptionType"] as? String, "recent")
    }

    func testTokenlessAndGarbageEntriesIgnored() {
        let garbage = Data("not json".utf8)
        let empty = try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": ["accessToken": ""]])
        XCTAssertNil(CredentialStore.bestCredential(among: [garbage, empty]))
        XCTAssertNotNil(CredentialStore.bestCredential(among: [garbage, blob(sub: "max", expiresAt: future)]))
    }
}
