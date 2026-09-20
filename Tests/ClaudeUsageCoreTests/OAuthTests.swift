// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import ClaudeUsageCore

final class PKCETests: XCTestCase {
    // RFC 7636 appendix B: the one published verifier/challenge pair.
    func testChallengeIsBase64URLOfSHA256() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(ClaudeOAuth.challenge(for: verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testFreshExchangeIsUnpredictable() {
        let a = ClaudeOAuth.Exchange.fresh(), b = ClaudeOAuth.Exchange.fresh()
        XCTAssertNotEqual(a.verifier, b.verifier)
        XCTAssertNotEqual(a.state, b.state)
        // 32 random bytes, base64url, no padding.
        XCTAssertEqual(a.verifier.count, 43)
        XCTAssertNil(a.verifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
    }
}

final class AuthorizeURLTests: XCTestCase {
    private let exchange = ClaudeOAuth.Exchange(verifier: "v", state: "s")

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testPointsAtClaudeAIWithClaudeCodesClient() {
        let url = ClaudeOAuth.authorizeURL(for: exchange, port: 51234)
        XCTAssertEqual(url.host, "claude.com")
        XCTAssertEqual(url.path, "/cai/oauth/authorize")
        let q = query(url)
        XCTAssertEqual(q["client_id"], "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
        XCTAssertEqual(q["response_type"], "code")
        XCTAssertEqual(q["code"], "true")
        XCTAssertEqual(q["redirect_uri"], "http://localhost:51234/callback")
        XCTAssertEqual(q["code_challenge_method"], "S256")
        XCTAssertEqual(q["code_challenge"], ClaudeOAuth.challenge(for: "v"))
        XCTAssertEqual(q["state"], "s")
    }

    // Reading usage needs nothing more; asking for inference or API-key
    // scopes would be asking for power the app has no use for.
    func testAsksForProfileScopeOnly() {
        XCTAssertEqual(query(ClaudeOAuth.authorizeURL(for: exchange, port: 1))["scope"], "user:profile")
    }
}

final class CallbackParsingTests: XCTestCase {
    func testCodeIsAcceptedWhenStateMatches() {
        let result = ClaudeOAuth.code(fromRequestTarget: "/callback?code=abc123&state=xyz", expectedState: "xyz")
        XCTAssertEqual(try result.get(), "abc123")
    }

    func testStateMismatchIsRejected() {
        let result = ClaudeOAuth.code(fromRequestTarget: "/callback?code=abc&state=other", expectedState: "xyz")
        XCTAssertEqual(result.failure, .stateMismatch)
    }

    func testOtherPathsAreNotTheCallback() {
        XCTAssertEqual(ClaudeOAuth.code(fromRequestTarget: "/favicon.ico", expectedState: "s").failure, .notTheCallback)
    }

    func testProviderErrorIsSurfaced() {
        let result = ClaudeOAuth.code(fromRequestTarget: "/callback?error=access_denied&state=s", expectedState: "s")
        XCTAssertEqual(result.failure, .denied("access_denied"))
    }
}

final class TokenExchangeTests: XCTestCase {
    private let exchange = ClaudeOAuth.Exchange(verifier: "verifier", state: "state")

    private func body(_ request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
    }

    func testExchangeRequestMatchesClaudeCodes() {
        let request = ClaudeOAuth.exchangeRequest(code: "the-code", for: exchange, port: 4000)
        XCTAssertEqual(request.url, ClaudeOAuth.tokenURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let b = body(request)
        XCTAssertEqual(b["grant_type"] as? String, "authorization_code")
        XCTAssertEqual(b["code"] as? String, "the-code")
        XCTAssertEqual(b["redirect_uri"] as? String, "http://localhost:4000/callback")
        XCTAssertEqual(b["client_id"] as? String, ClaudeOAuth.clientID)
        XCTAssertEqual(b["code_verifier"] as? String, "verifier")
        XCTAssertEqual(b["state"] as? String, "state")
    }

    func testRefreshRequestCarriesTheRefreshToken() {
        let b = body(ClaudeOAuth.refreshRequest(refreshToken: "r-1"))
        XCTAssertEqual(b["grant_type"] as? String, "refresh_token")
        XCTAssertEqual(b["refresh_token"] as? String, "r-1")
        XCTAssertEqual(b["client_id"] as? String, ClaudeOAuth.clientID)
    }

    func testTokenResponseParses() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let json: [String: Any] = ["access_token": "a", "refresh_token": "r", "expires_in": 3600,
                                   "scope": "user:profile"]
        let tokens = try XCTUnwrap(ClaudeOAuth.Tokens(json: json, now: now))
        XCTAssertEqual(tokens.accessToken, "a")
        XCTAssertEqual(tokens.refreshToken, "r")
        XCTAssertEqual(tokens.expiresAt, now.addingTimeInterval(3600))
    }

    func testTokenResponseWithoutAccessTokenIsRejected() {
        XCTAssertNil(ClaudeOAuth.Tokens(json: ["refresh_token": "r"], now: Date()))
    }
}

/// The app's own login is stored in the same shape Claude Code uses, so the
/// one parser serves both.
final class OwnLoginBlobTests: XCTestCase {
    func testBlobRoundTripsThroughTheSharedParser() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tokens = ClaudeOAuth.Tokens(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(60))
        let plan = ClaudeOAuth.Plan(rateLimitTier: "default_claude_max_5x", subscriptionType: "max")
        let blob = OwnLogin.blob(tokens: tokens, plan: plan)
        let parsed = try CredentialStore.parse(blob)
        XCTAssertEqual(parsed.accessToken, "a")
        XCTAssertEqual(parsed.planLabel, "Max 5x")
        XCTAssertEqual(parsed.expiresAt, now.addingTimeInterval(60))
        XCTAssertEqual(OwnLogin.refreshToken(in: blob), "r")
    }

    func testPlanIsReadFromTheProfile() {
        let profile: [String: Any] = [
            "account": ["has_claude_max": true, "has_claude_pro": false],
            "organization": ["organization_type": "claude_max", "rate_limit_tier": "default_claude_max_5x"],
        ]
        let plan = ClaudeOAuth.Plan(profile: profile)
        XCTAssertEqual(plan.rateLimitTier, "default_claude_max_5x")
        XCTAssertEqual(plan.subscriptionType, "max")
    }

    func testProPlanWithoutATier() {
        let profile: [String: Any] = ["account": ["has_claude_max": false, "has_claude_pro": true],
                                      "organization": ["organization_type": "claude_pro"]]
        XCTAssertEqual(ClaudeOAuth.Plan(profile: profile).subscriptionType, "pro")
        XCTAssertEqual(CredentialStore.planLabel(tier: "", subscription: "pro"), "Pro")
    }

    // A refresh that lands must replace the stored tokens but keep the plan,
    // which only the profile endpoint knows.
    func testRefreshedBlobKeepsThePlan() throws {
        let old = OwnLogin.blob(tokens: .init(accessToken: "a", refreshToken: "r", expiresAt: Date()),
                                plan: .init(rateLimitTier: "default_claude_max_5x", subscriptionType: "max"))
        let renewed = OwnLogin.blob(tokens: .init(accessToken: "a2", refreshToken: "r2", expiresAt: Date()),
                                    plan: OwnLogin.plan(in: old))
        XCTAssertEqual(try CredentialStore.parse(renewed).planLabel, "Max 5x")
        XCTAssertEqual(OwnLogin.refreshToken(in: renewed), "r2")
    }
}

final class OwnLoginRefreshTests: XCTestCase {
    private let plan = ClaudeOAuth.Plan(rateLimitTier: "default_claude_max_5x", subscriptionType: "max")
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func blob(expiringIn seconds: TimeInterval) -> Data {
        OwnLogin.blob(tokens: .init(accessToken: "old", refreshToken: "r", expiresAt: now.addingTimeInterval(seconds)), plan: plan)
    }

    func testFreshLoginIsServedWithoutARefresh() {
        var refreshed = false
        let served = OwnLogin.current(now: now, stored: { self.blob(expiringIn: 3600) },
                                      refresh: { _ in refreshed = true; return nil }, save: { _ in })
        XCTAssertNotNil(served)
        XCTAssertFalse(refreshed)
    }

    func testLapsingLoginIsRefreshedAndSaved() throws {
        var saved: Data?
        let served = OwnLogin.current(now: now, stored: { self.blob(expiringIn: 60) },
                                      refresh: { _ in ["access_token": "new", "expires_in": 3600] },
                                      save: { saved = $0 })
        let parsed = try CredentialStore.parse(try XCTUnwrap(served))
        XCTAssertEqual(parsed.accessToken, "new")
        XCTAssertEqual(parsed.planLabel, "Max 5x")
        XCTAssertEqual(saved, served)
        // No new refresh token in the reply: the old one is kept.
        XCTAssertEqual(OwnLogin.refreshToken(in: try XCTUnwrap(served)), "r")
    }

    func testFailedRefreshYieldsNothing() {
        XCTAssertNil(OwnLogin.current(now: now, stored: { self.blob(expiringIn: -5) },
                                      refresh: { _ in nil }, save: { _ in XCTFail("nothing to save") }))
    }

    func testNoOwnLoginIsNil() {
        XCTAssertNil(OwnLogin.current(now: now, stored: { nil }, refresh: { _ in nil }, save: { _ in }))
    }
}

/// The listener end to end, with the browser played by URLSession and the
/// token endpoint by a closure.
final class SignInListenerTests: XCTestCase {
    private func get(_ url: URL) -> (Int, String) {
        var status = 0, body = ""
        let done = expectation(description: "reply")
        URLSession.shared.dataTask(with: url) { data, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            body = String(decoding: data ?? Data(), as: UTF8.self)
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 5)
        return (status, body)
    }

    private func callback(from authorize: URL, query: String) -> URL {
        let port = URLComponents(url: authorize, resolvingAgainstBaseURL: false)!
            .queryItems!.first { $0.name == "redirect_uri" }!.value!
            .split(separator: ":").last!.split(separator: "/").first!
        return URL(string: "http://localhost:\(port)/callback?\(query)")!
    }

    func testCodeWithMatchingStateSignsIn() throws {
        var saved: Data?
        var exchanged: [String: Any]?
        let flow = SignIn(post: { request in
            if request.url == ClaudeOAuth.tokenURL {
                exchanged = (try? JSONSerialization.jsonObject(with: request.httpBody!)) as? [String: Any]
                return ["access_token": "at", "refresh_token": "rt", "expires_in": 3600]
            }
            return ["account": ["has_claude_max": true], "organization": ["rate_limit_tier": "default_claude_max_5x"]]
        }, save: { saved = $0; return true })
        let finished = expectation(description: "outcome")
        var outcome: SignIn.Outcome?
        let authorize = try flow.start { outcome = $0; finished.fulfill() }
        let state = URLComponents(url: authorize, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!

        let (status, body) = get(callback(from: authorize, query: "code=c0de&state=\(state)"))
        wait(for: [finished], timeout: 5)

        XCTAssertEqual(status, 200)
        XCTAssertTrue(body.contains("signed in"))
        XCTAssertEqual(outcome, .signedIn(planLabel: "Max 5x"))
        XCTAssertEqual(exchanged?["code"] as? String, "c0de")
        XCTAssertEqual(exchanged?["state"] as? String, state)
        XCTAssertEqual(try CredentialStore.parse(try XCTUnwrap(saved)).accessToken, "at")
    }

    func testWrongStateIsRefusedAndTheAttemptKeepsWaiting() throws {
        let flow = SignIn(post: { _ in XCTFail("no exchange"); return nil }, save: { _ in false })
        var ended = false
        let authorize = try flow.start { _ in ended = true }
        let (status, _) = get(callback(from: authorize, query: "code=c&state=nope"))
        XCTAssertEqual(status, 400)
        XCTAssertFalse(ended)
        flow.cancel()
    }

    func testDenialEndsTheAttempt() throws {
        let flow = SignIn(post: { _ in XCTFail("no exchange"); return nil }, save: { _ in false })
        let finished = expectation(description: "outcome")
        var outcome: SignIn.Outcome?
        let authorize = try flow.start { outcome = $0; finished.fulfill() }
        let state = URLComponents(url: authorize, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
        _ = get(callback(from: authorize, query: "error=access_denied&state=\(state)"))
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(outcome, .denied("access_denied"))
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let f) = self { return f }
        return nil
    }
}
