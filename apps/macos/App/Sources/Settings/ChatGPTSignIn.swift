// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Network

/// Signs in with ChatGPT in the system browser (docs/reviews/chatgpt-login.md 4.7): starts
/// the loopback listener, opens the authorization URL, waits for the callback, keeps the
/// issued client id, exchanges the code and hands the credential to the shared session.
struct ChatGPTSignIn: Sendable {
  typealias Exchange =
    @Sendable (AuthorizationCode, String, AuthorizationAttempt, ChatGPTEndpoints) async throws
    -> ChatGPTCredential

  let account: ChatGPTAccount
  var appName = "Dict"
  /// Opens the URL in the default browser.
  var openURL: @Sendable (URL) async -> Void
  var exchange: Exchange = { code, clientID, attempt, endpoints in
    try await exchangeAuthorizationCode(
      code, clientID: clientID, attempt: attempt, endpoints: endpoints)
  }
  /// How long the browser has to come back.
  var timeout = Duration.seconds(300)
  /// The callback port of the documentation's examples, used when it is free.
  var preferredPort: UInt16 = 1455

  /// Throws a `ChatGPTSignInError`, a `ModelError.network`, a `KeychainError`, or
  /// `CancellationError` when the calling task is cancelled.
  func run() async throws -> ChatGPTCredential {
    var registration = try account.registrations.load()
    // The listener is up before the browser opens; its port is the redirect URI's.
    let receiver = try await LoopbackReceiver.start(preferring: preferredPort)
    defer { receiver.stop() }
    let attempt = AuthorizationAttempt.make(port: receiver.port)
    let hint = registration.clientID == nil ? nil : account.savedCredential?.idToken
    await openURL(
      attempt.url(
        account.endpoints, registration: registration, appName: appName, idTokenHint: hint))

    let code: AuthorizationCode
    do {
      code = try attempt.callback(try await receiver.callback(timeout: timeout))
    } catch ChatGPTSignInError.denied("invalid_client") {
      try forgetClient(&registration)
      throw ChatGPTSignInError.denied("invalid_client")
    }
    // Kept before the exchange, so that a failed exchange keeps the registration.
    if let issued = code.clientID, issued != registration.clientID {
      registration.clientID = issued
      try account.registrations.save(registration)
    }
    guard let clientID = registration.clientID else { throw ChatGPTSignInError.missingClientID }

    let credential: ChatGPTCredential
    do {
      credential = try await exchange(code, clientID, attempt, account.endpoints)
    } catch ChatGPTSignInError.tokenRejected("invalid_client") {
      try forgetClient(&registration)
      throw ChatGPTSignInError.tokenRejected("invalid_client")
    }
    registration.email = credential.email
    try account.registrations.save(registration)
    try await account.session.signedIn(credential)
    Log.ui.info(
      "ChatGPT signed in on port \(receiver.port, privacy: .public), plan usage \(credential.canUsePlan, privacy: .public)"
    )
    return credential
  }

  /// The server no longer knows the issued client: the next sign-in registers again.
  private func forgetClient(_ registration: inout ChatGPTRegistration) throws {
    registration.clientID = nil
    try account.registrations.save(registration)
  }
}

/// A one-shot HTTP listener on 127.0.0.1 that waits for `GET /auth/callback` (never on
/// other interfaces). Other paths, such as a browser's favicon request, get a 404.
final class LoopbackReceiver: Sendable {
  let port: UInt16
  private let listener: NWListener
  private let urls: AsyncStream<URL>
  private let continuation: AsyncStream<URL>.Continuation

  private init(
    listener: NWListener, port: UInt16, urls: AsyncStream<URL>,
    continuation: AsyncStream<URL>.Continuation
  ) {
    self.listener = listener
    self.port = port
    self.urls = urls
    self.continuation = continuation
  }

  /// Listens on `port` when it is free, otherwise on a port the system picks.
  static func start(preferring port: UInt16) async throws -> LoopbackReceiver {
    do {
      return try await start(on: NWEndpoint.Port(rawValue: port) ?? .any)
    } catch {
      return try await start(on: .any)
    }
  }

  private static func start(on port: NWEndpoint.Port) async throws -> LoopbackReceiver {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
    parameters.allowLocalEndpointReuse = false
    let listener = try NWListener(using: parameters)
    let (urls, continuation) = AsyncStream<URL>.makeStream()
    let queue = DispatchQueue(label: "dict.chatgpt.loopback")
    listener.newConnectionHandler = { connection in
      connection.start(queue: queue)
      Self.serve(connection, port: listener.port?.rawValue ?? 0, continuation: continuation)
    }
    let ready = try await withCheckedThrowingContinuation {
      (started: CheckedContinuation<UInt16, Error>) in
      // The handler runs on the serial queue, so the flag needs no lock.
      let once = ResumeOnce()
      @Sendable func resume(_ result: Result<UInt16, Error>) {
        guard !once.done else { return }
        once.done = true
        started.resume(with: result)
      }
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready: resume(.success(listener.port?.rawValue ?? 0))
        case .failed(let error): resume(.failure(error))
        case .cancelled: resume(.failure(CancellationError()))
        default: break
        }
      }
      listener.start(queue: queue)
    }
    listener.stateUpdateHandler = nil
    return LoopbackReceiver(
      listener: listener, port: ready, urls: urls, continuation: continuation)
  }

  /// The first callback URL; throws `ChatGPTSignInError.timedOut` after `timeout`, or
  /// `CancellationError` when cancelled.
  func callback(timeout: Duration) async throws -> URL {
    let urls = urls
    return try await withThrowingTaskGroup(of: URL.self) { group in
      group.addTask {
        for await url in urls { return url }
        throw CancellationError()
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw ChatGPTSignInError.timedOut
      }
      defer { group.cancelAll() }
      guard let url = try await group.next() else { throw CancellationError() }
      return url
    }
  }

  func stop() {
    continuation.finish()
    listener.cancel()
  }

  /// Reads one request, answers it and closes the connection.
  private static func serve(
    _ connection: NWConnection, port: UInt16, continuation: AsyncStream<URL>.Continuation
  ) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
      data, _, _, _ in
      let target = data.flatMap(requestTarget)
      let url = target.flatMap { URL(string: "http://127.0.0.1:\(port)\($0)") }
      let isCallback = url?.path() == ChatGPTAuth.callbackPath
      let response = isCallback ? page : notFound
      connection.send(
        content: Data(response.utf8),
        completion: .contentProcessed { _ in connection.cancel() })
      if isCallback, let url { continuation.yield(url) }
    }
  }

  /// The target of a `GET <target> HTTP/1.1` request line.
  static func requestTarget(_ data: Data) -> String? {
    let line =
      String(decoding: data.prefix(8 * 1024), as: UTF8.self)
      .split(separator: "\r\n", maxSplits: 1).first ?? ""
    let parts = line.split(separator: " ")
    guard parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/") else { return nil }
    return String(parts[1])
  }

  private static let page = response(
    status: "200 OK",
    body: """
      <!doctype html><html><head><meta charset="utf-8"><title>Dict</title></head>
      <body style="font: 15px -apple-system, sans-serif; margin: 4em; text-align: center">
      <p>\(String(
        localized: "You can close this tab and return to Dict.", table: "Settings",
        comment: "Browser page after signing in with ChatGPT"))</p></body></html>
      """)
  private static let notFound = response(status: "404 Not Found", body: "")

  private static func response(status: String, body: String) -> String {
    "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
      + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
  }
}

/// Whether a continuation was resumed; touched only on the listener's serial queue.
private final class ResumeOnce: @unchecked Sendable {
  var done = false
}
