// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation
import Network

/// One sign-in, from opening the browser to a saved login.
///
/// The browser is sent to claude.ai with a redirect back to a port on
/// localhost that this object listens on, the way Claude Code does. When the
/// browser comes back with a code, the code is traded for tokens, the plan is
/// read from the profile endpoint, and the result is saved as the app's own
/// login. One attempt at a time; a second `start` while one is waiting
/// cancels the first, so a user who clicks twice gets one browser tab that
/// works rather than two that fight over the state.
public final class SignIn {
    public struct NoPort: Error {}

    public enum Outcome: Equatable {
        case signedIn(planLabel: String)
        case denied(String)
        case failed(String)
        case timedOut
    }

    /// How long the browser tab is given. Long enough to find a password
    /// manager; short enough that a forgotten tab does not keep a port open
    /// all day.
    public static let timeout: TimeInterval = 5 * 60

    private let queue = DispatchQueue(label: "com.nicholaspsmith.ClaudeUsage.signin")
    private var listener: NWListener?
    private var exchange: ClaudeOAuth.Exchange?
    private var port: UInt16 = 0
    private var finished = false
    private var completion: ((Outcome) -> Void)?
    private let post: (URLRequest) -> [String: Any]?
    private let save: (Data) -> Bool

    public init(post: @escaping (URLRequest) -> [String: Any]? = OwnLogin.post,
                save: @escaping (Data) -> Bool = { OwnLogin.save($0) }) {
        self.post = post
        self.save = save
    }

    /// Listens, then hands back the URL to open. `completion` is called once,
    /// on the sign-in queue, however the attempt ends.
    public func start(completion: @escaping (Outcome) -> Void) throws -> URL {
        cancel()
        let exchange = ClaudeOAuth.Exchange.fresh()
        // Loopback only, v4 and v6 both — the browser resolves "localhost" to
        // whichever it likes — and never the LAN.
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters, on: .any)
        self.exchange = exchange
        self.completion = completion
        self.finished = false

        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.port = listener.port?.rawValue ?? 0
                ready.signal()
            case .failed, .cancelled:
                ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.start(queue: queue)
        self.listener = listener
        _ = ready.wait(timeout: .now() + 2)
        guard port != 0 else {
            cancel()
            throw NoPort()
        }

        queue.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in self?.finish(.timedOut) }
        return ClaudeOAuth.authorizeURL(for: exchange, port: port)
    }

    public func cancel() {
        queue.sync {
            listener?.cancel()
            listener = nil
            exchange = nil
            completion = nil
            finished = true
        }
    }

    // MARK: - The callback

    /// Reads one HTTP request line, answers it, and — if it was the callback
    /// we are waiting for — finishes the sign-in.
    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = String(decoding: data ?? Data(), as: UTF8.self)
            let target = request.split(separator: "\r\n", maxSplits: 1).first
                .flatMap { line in line.split(separator: " ").dropFirst().first }
                .map(String.init) ?? "/"
            guard let exchange = self.exchange, !self.finished else {
                self.reply(connection, status: "404 Not Found", body: "<p>No sign-in is waiting.</p>")
                return
            }
            switch ClaudeOAuth.code(fromRequestTarget: target, expectedState: exchange.state) {
            case .success(let code):
                self.reply(connection, status: "200 OK", body: Self.doneHTML)
                self.complete(code: code, exchange: exchange)
            case .failure(.notTheCallback):
                self.reply(connection, status: "404 Not Found", body: "")
            case .failure(.stateMismatch):
                // Not ours. Say nothing useful and keep waiting for the real one.
                self.reply(connection, status: "400 Bad Request", body: "<p>That sign-in is not the one this app is waiting for.</p>")
            case .failure(.denied(let reason)):
                self.reply(connection, status: "200 OK", body: "<p>Sign-in cancelled. You can close this tab.</p>")
                self.finish(.denied(reason))
            }
        }
    }

    private func reply(_ connection: NWConnection, status: String, body: String) {
        let html = "<!doctype html><meta charset=utf-8><title>Claude Usage</title>"
            + "<body style=\"font-family:-apple-system,sans-serif;padding:3em;text-align:center\">\(body)</body>"
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data((head + html).utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    static let doneHTML = "<h2>Claude Usage is signed in.</h2><p>You can close this tab and go back to the menu bar.</p>"

    /// Trade the code for tokens, read the plan, save. Network calls, but
    /// already on the sign-in queue.
    private func complete(code: String, exchange: ClaudeOAuth.Exchange) {
        guard let json = post(ClaudeOAuth.exchangeRequest(code: code, for: exchange, port: port)),
              let tokens = ClaudeOAuth.Tokens(json: json)
        else { return finish(.failed("The token exchange was refused")) }
        // The plan is a nicety: a profile fetch that fails leaves the label
        // blank rather than failing the sign-in.
        let profile = post(ClaudeOAuth.profileRequest(accessToken: tokens.accessToken)) ?? [:]
        let plan = ClaudeOAuth.Plan(profile: profile)
        guard save(OwnLogin.blob(tokens: tokens, plan: plan)) else {
            return finish(.failed("The login could not be saved to the Keychain"))
        }
        CredentialStore.invalidate()
        finish(.signedIn(planLabel: CredentialStore.planLabel(tier: plan.rateLimitTier,
                                                              subscription: plan.subscriptionType)))
    }

    private func finish(_ outcome: Outcome) {
        guard !finished else { return }
        finished = true
        listener?.cancel()
        listener = nil
        exchange = nil
        let done = completion
        completion = nil
        done?(outcome)
    }
}
