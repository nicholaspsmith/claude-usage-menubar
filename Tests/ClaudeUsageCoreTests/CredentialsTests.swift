import XCTest
@testable import ClaudeUsageCore

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

final class RelativeTimeTests: XCTestCase {

    func testShortUnitsEscalate() {
        XCTAssertEqual(RelativeTime.short(12), "12s")
        XCTAssertEqual(RelativeTime.short(180), "3m")
        XCTAssertEqual(RelativeTime.short(7_200), "2h")
        XCTAssertEqual(RelativeTime.short(200_000), "2d")
    }

    func testAgoPhrasing() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(RelativeTime.ago(now.addingTimeInterval(-180), now: now), "updated 3m ago")
        XCTAssertEqual(RelativeTime.ago(nil, now: now), "never updated")
    }

    // "updated 0s ago" reads like a stuck clock.
    func testFreshReadsAsJustNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(RelativeTime.ago(now, now: now), "updated just now")
        XCTAssertEqual(RelativeTime.ago(now.addingTimeInterval(-2), now: now), "updated just now")
    }

    // Sleep or an NTP correction can put the stamp in the future; it must not
    // render a negative age.
    func testClockGoingBackwards() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(RelativeTime.ago(now.addingTimeInterval(120), now: now), "updated just now")
    }
}
