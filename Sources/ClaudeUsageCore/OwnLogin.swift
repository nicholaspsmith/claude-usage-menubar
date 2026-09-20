// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// The login this app holds for itself, as opposed to the one it borrows
/// from Claude Code.
///
/// Signing in from the menu produces a token of our own, with a refresh
/// token of our own, so the app can keep itself signed in without waiting
/// for the CLI to run. It is kept apart from Claude Code's credential on
/// purpose: refresh tokens rotate, and refreshing the CLI's would sign the
/// CLI out. Nothing here ever writes to `Claude Code-credentials`.
public enum OwnLogin {
    /// Its own Keychain item, in Claude Code's JSON shape so the one parser
    /// reads both. Written and read through `/usr/bin/security` for the
    /// reason `CredentialStore.securityToolSecret` explains: this binary is
    /// signed without a Team ID, so an item it creates itself is pinned to
    /// its CDHash and prompts for the login password after every rebuild.
    /// An item the tool writes sits in the tool's partition and never prompts.
    public static let service = "Claude Usage-credentials"
    static var account: String { NSUserName() }

    /// How early a token is refreshed. Generous: a refresh costs one request
    /// and a lapse costs a poll's worth of "Sign-in expired".
    public static let refreshMargin: TimeInterval = 10 * 60

    // MARK: - The blob

    public static func blob(tokens: ClaudeOAuth.Tokens, plan: ClaudeOAuth.Plan) -> Data {
        var oauth: [String: Any] = [
            "accessToken": tokens.accessToken,
            "scopes": ClaudeOAuth.scopes,
            "rateLimitTier": plan.rateLimitTier,
            "subscriptionType": plan.subscriptionType,
        ]
        if let refresh = tokens.refreshToken { oauth["refreshToken"] = refresh }
        if let expires = tokens.expiresAt { oauth["expiresAt"] = expires.timeIntervalSince1970 * 1000 }
        return (try? JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth])) ?? Data()
    }

    static func oauth(in blob: Data) -> [String: Any] {
        ((try? JSONSerialization.jsonObject(with: blob)) as? [String: Any])?["claudeAiOauth"] as? [String: Any] ?? [:]
    }

    public static func refreshToken(in blob: Data) -> String? {
        let token = oauth(in: blob)["refreshToken"] as? String
        return token?.isEmpty == false ? token : nil
    }

    public static func plan(in blob: Data) -> ClaudeOAuth.Plan {
        let o = oauth(in: blob)
        return ClaudeOAuth.Plan(rateLimitTier: o["rateLimitTier"] as? String ?? "",
                                subscriptionType: o["subscriptionType"] as? String ?? "")
    }

    // MARK: - Storage

    public static func stored() -> Data? {
        guard let result = CredentialStore.securityToolSecret(service: service, account: account),
              case .success(let data) = result
        else { return nil }
        return data
    }

    /// `-U` updates in place, so signing in again replaces rather than piles
    /// up — the very accumulation that once had the CLI's own items reporting
    /// an expired Pro plan for a live Max account.
    ///
    /// The command goes to the tool's interactive mode on stdin rather than
    /// as arguments, so the token never appears in `ps`. The blob is JSON
    /// from `JSONSerialization` — no single quotes in it — which is what
    /// makes the one-line quoting safe.
    @discardableResult
    public static func save(_ blob: Data) -> Bool {
        let json = String(decoding: blob, as: UTF8.self)
        guard !json.contains("'") else { return false }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: CredentialStore.securityToolPath)
        task.arguments = ["-i"]
        let input = Pipe()
        task.standardInput = input
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return false }
        let line = "add-generic-password -U -s '\(service)' -a '\(account)' -w '\(json)'\n"
        input.fileHandleForWriting.write(Data(line.utf8))
        try? input.fileHandleForWriting.close()
        task.waitUntilExit()
        return task.terminationStatus == 0 && stored() != nil
    }

    @discardableResult
    public static func forget() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: CredentialStore.securityToolPath)
        task.arguments = ["delete-generic-password", "-s", service, "-a", account]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    public static var exists: Bool { stored() != nil }

    // MARK: - Keeping it alive

    /// The stored login, refreshed first if it is about to lapse.
    ///
    /// Nil when there is no own login, or it has lapsed and the refresh did
    /// not land — the caller then falls back to Claude Code's credential, and
    /// the stale item is left where it is so the next poll can try again.
    public static func current(now: Date = Date(),
                               stored: () -> Data? = OwnLogin.stored,
                               refresh: (URLRequest) -> [String: Any]? = OwnLogin.post,
                               save: (Data) -> Void = { OwnLogin.save($0) }) -> Data? {
        guard let held = stored() else { return nil }
        let expiry = CredentialStore.expiry(oauth(in: held)["expiresAt"])
        let lapsing = expiry.map { $0.addingTimeInterval(-refreshMargin) <= now } ?? false
        guard lapsing else { return held }
        guard let token = refreshToken(in: held),
              let json = refresh(ClaudeOAuth.refreshRequest(refreshToken: token)),
              let tokens = ClaudeOAuth.Tokens(json: json, now: now)
        else { return nil }
        // A refresh reply need not carry a new refresh token; keep the old
        // one in that case rather than dropping the ability to refresh again.
        let kept = ClaudeOAuth.Tokens(accessToken: tokens.accessToken,
                                      refreshToken: tokens.refreshToken ?? token,
                                      expiresAt: tokens.expiresAt)
        let renewed = blob(tokens: kept, plan: plan(in: held))
        save(renewed)
        return renewed
    }

    /// One JSON round trip, synchronous: the callers are already off the
    /// main thread, and a sign-in is nothing to keep a queue busy over.
    public static func post(_ request: URLRequest) -> [String: Any]? {
        var result: [String: Any]?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { done.signal() }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else { return }
            result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }.resume()
        _ = done.wait(timeout: .now() + 35)
        return result
    }
}
