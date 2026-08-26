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

/// The cache exists because every Keychain read is a chance at a password
/// prompt, and the app polls once a minute. See `CredentialStore.secret`
/// for why the prompt kept coming back.
final class CredentialCacheTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func login(expiringIn seconds: TimeInterval?, from now: Date) -> ClaudeCredentials {
        ClaudeCredentials(accessToken: "tok",
                          expiresAt: seconds.map { now.addingTimeInterval($0) },
                          planLabel: "Max 5x")
    }

    /// A counting loader, so the tests can assert on reads rather than results.
    private func loader(_ result: @escaping () -> Result<ClaudeCredentials, CredentialStore.LoadFailure>)
        -> (() -> Result<ClaudeCredentials, CredentialStore.LoadFailure>, () -> Int) {
        var reads = 0
        return ({ reads += 1; return result() }, { reads })
    }

    func testValidLoginIsReadOnceAcrossManyPolls() {
        let cache = CredentialCache()
        let creds = login(expiringIn: 43_200, from: t0)
        let (load, reads) = loader { .success(creds) }

        for minute in 0..<60 {
            _ = cache.value(now: t0.addingTimeInterval(Double(minute) * 60), reload: load)
        }
        XCTAssertEqual(reads(), 1)
    }

    func testLapsedLoginIsReRead() {
        let cache = CredentialCache()
        let (load, reads) = loader { .success(self.login(expiringIn: 3_600, from: self.t0)) }

        _ = cache.value(now: t0, reload: load)
        _ = cache.value(now: t0.addingTimeInterval(7_200), reload: load)
        XCTAssertEqual(reads(), 2)
    }

    // Re-read slightly early: a token that lapses mid-request is a probe
    // wasted and a "Sign-in expired" flash in the menu.
    func testMarginReReadsBeforeTheTokenActuallyLapses() {
        let cache = CredentialCache()
        let (load, reads) = loader { .success(self.login(expiringIn: 3_600, from: self.t0)) }

        _ = cache.value(now: t0, reload: load)
        _ = cache.value(now: t0.addingTimeInterval(3_600 - CredentialStore.renewMargin + 1), reload: load)
        XCTAssertEqual(reads(), 2)
    }

    // A credential with no expiry can't be aged out, but it must still be
    // cached — otherwise the file-backed path polls the disk every minute.
    func testUndatedLoginIsCached() {
        let cache = CredentialCache()
        let (load, reads) = loader { .success(self.login(expiringIn: nil, from: self.t0)) }

        _ = cache.value(now: t0, reload: load)
        _ = cache.value(now: t0.addingTimeInterval(86_400), reload: load)
        XCTAssertEqual(reads(), 1)
    }

    // A failed re-read must not leave the lapsed login in place: the menu has
    // to be able to say "expired" and then recover on its own.
    func testFailedReloadDropsTheStoredLogin() {
        let cache = CredentialCache()
        var fail = false
        let (load, reads) = loader {
            fail ? .failure(.notFound) : .success(self.login(expiringIn: 3_600, from: self.t0))
        }

        _ = cache.value(now: t0, reload: load)
        fail = true
        let failed = cache.value(now: t0.addingTimeInterval(7_200), reload: load)
        XCTAssertEqual(failed.failureMessage, CredentialStore.LoadFailure.notFound.message)

        // Still failing, still asking — not serving the corpse of the old one.
        _ = cache.value(now: t0.addingTimeInterval(7_260), reload: load)
        XCTAssertEqual(reads(), 3)
    }

    // What a 401 has to do: the token is valid by its own clock, but the
    // server disagrees, so the copy in hand is the wrong one.
    func testInvalidateForcesOneReRead() {
        let cache = CredentialCache()
        let (load, reads) = loader { .success(self.login(expiringIn: 43_200, from: self.t0)) }

        _ = cache.value(now: t0, reload: load)
        cache.invalidate()
        _ = cache.value(now: t0.addingTimeInterval(60), reload: load)
        _ = cache.value(now: t0.addingTimeInterval(120), reload: load)
        XCTAssertEqual(reads(), 2)
    }
}

/// Parsing what `/usr/bin/security` hands back.
final class SecurityToolTests: XCTestCase {

    // `security ... -w` prints the secret and adds a newline of its own. That
    // newline is not part of the credential and breaks nothing here, but it
    // would ride along into anything less forgiving than JSONSerialization.
    func testTrailingNewlineStripped() {
        let json = #"{"claudeAiOauth":{}}"#
        XCTAssertEqual(CredentialStore.strippingTrailingNewline(Data((json + "\n").utf8)),
                       Data(json.utf8))
    }

    // Only the one the tool added — a second belongs to the secret.
    func testOnlyTheToolsOwnNewlineIsStripped() {
        XCTAssertEqual(CredentialStore.strippingTrailingNewline(Data("a\n\n".utf8)), Data("a\n".utf8))
        XCTAssertEqual(CredentialStore.strippingTrailingNewline(Data("a".utf8)), Data("a".utf8))
        XCTAssertEqual(CredentialStore.strippingTrailingNewline(Data()), Data())
    }

    // 44 is the tool's exit status for errSecItemNotFound; everything else it
    // only spells out in its message, so the message is what gets read.
    func testExitStatusMapping() {
        XCTAssertEqual(CredentialStore.failure(forSecurityExit: 44, stderr: ""), .notFound)
        XCTAssertEqual(CredentialStore.failure(forSecurityExit: 36,
            stderr: "security: SecKeychainSearchCopyNext: User interaction is not allowed."),
            .interactionNotAllowed)
        XCTAssertEqual(CredentialStore.failure(forSecurityExit: 128,
            stderr: "security: SecKeychainSearchCopyNext: User canceled the operation."),
            .denied)
        XCTAssertEqual(CredentialStore.failure(forSecurityExit: 1, stderr: "something else"), .status(1))
    }
}
