// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A `TextModel` on the user's ChatGPT plan: `POST <api>/responses` with the signed-in
/// account's access token (docs/reviews/chatgpt-login.md 4.2–4.6). Not a general Responses
/// client. A 401 refreshes the token and retries once; parameters the plan rejects are not
/// dropped and retried, the 400 surfaces with the server's message.
public struct ResponsesModel: TextModel {
  public let model: String
  public let thinking: ThinkingSetting
  public let rules: [ThinkingRule]
  public let endpoints: ChatGPTEndpoints
  private let tokens: any AccessTokenSource
  private let session: URLSession
  private let makeWatchdog: @Sendable () -> any ModelWatchdog
  private let timeouts: ModelTimeouts

  public init(
    model: String, thinking: ThinkingSetting, rules: [ThinkingRule],
    endpoints: ChatGPTEndpoints, tokens: any AccessTokenSource, session: URLSession = .shared,
    clock: some Clock<Duration> = ContinuousClock(), timeouts: ModelTimeouts = .standard
  ) {
    self.model = model
    self.thinking = thinking
    self.rules = rules
    self.endpoints = endpoints
    self.tokens = tokens
    self.session = session
    self.makeWatchdog = { Watchdog(clock: clock, timeouts: timeouts) }
    self.timeouts = timeouts
  }

  public func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try await run(request) { continuation.yield($0) }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Races the exchange against the watchdog, as `ChatCompletionsModel` does.
  private func run(
    _ request: ModelRequest, yield: @escaping @Sendable (StreamEvent) -> Void
  ) async throws {
    // Before the watchdog starts: a refresh is not the model being slow.
    let token = try await tokens.accessToken()
    let watchdog = makeWatchdog()
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await exchange(request, token: token, watchdog: watchdog, yield: yield)
      }
      group.addTask { throw ModelError.timedOut(try await watchdog.expiry()) }
      defer { group.cancelAll() }
      try await group.next()
    }
  }

  private func exchange(
    _ request: ModelRequest, token: String, watchdog: any ModelWatchdog,
    yield: @Sendable (StreamEvent) -> Void
  ) async throws {
    do {
      let body = responsesBody(request, model: model, thinking: thinking, rules: rules)
      var token = token
      var (bytes, response) = try await send(body, token: token)
      if response.statusCode == 401 {
        await tokens.rejected(token)
        token = try await tokens.accessToken()
        (bytes, response) = try await send(body, token: token)
      }
      guard (200..<300).contains(response.statusCode) else {
        throw try await failure(bytes, response, token: token)
      }

      var decoder = ResponsesStreamDecoder()
      var parser = SSEParser()
      for try await byte in bytes {
        guard let event = parser.push(byte) else { continue }
        watchdog.feed()
        try decoder.decode(event).forEach(yield)
        if decoder.isDone { return }
      }
      try decoder.finish().forEach(yield)
    } catch let error as URLError {
      if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
      throw ModelError.network(code: error.code.rawValue)
    }
  }

  private func send(_ body: JSONValue, token: String) async throws -> (
    URLSession.AsyncBytes, HTTPURLResponse
  ) {
    var request = URLRequest(url: endpoints.api.appending(path: "responses"))
    request.httpMethod = "POST"
    request.timeoutInterval = Double(timeouts.total.components.seconds) + 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.httpBody = body.jsonData()
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse else { throw ModelError.malformedResponse }
    return (bytes, http)
  }

  private func failure(
    _ bytes: URLSession.AsyncBytes, _ response: HTTPURLResponse, token: String
  ) async throws -> ModelError {
    var data = Data()
    for try await byte in bytes {
      data.append(byte)
      if data.count >= 64 * 1024 { break }
    }
    return chatGPTFailure(data, status: response.statusCode, token: token)
  }
}

/// Maps a failed ChatGPT-plan response body, with the token masked in any message.
func chatGPTFailure(_ data: Data, status: Int, token: String) -> ModelError {
  let json = try? JSONDecoder().decode(JSONValue.self, from: data)
  let error = responsesError(
    status: status, json.map { $0["error"] ?? $0 } ?? .string(String(decoding: data, as: UTF8.self))
  )
  guard case .badRequest(let message) = error, !token.isEmpty else { return error }
  return .badRequest(message: message.replacingOccurrences(of: token, with: "••••"))
}

/// The models the signed-in account may use, in the server's order: the slugs of
/// `GET <api>/models` whose `visibility` is "list". A 401 refreshes the token and asks once
/// more. Throws a `ModelError`.
public func listChatGPTModels(
  endpoints: ChatGPTEndpoints, tokens: any AccessTokenSource, session: URLSession = .shared,
  timeout: TimeInterval = 15
) async throws -> [String] {
  func get(_ token: String) async throws -> (Data, Int) {
    var request = URLRequest(url: modelListURL(baseURL: endpoints.api, style: .chatGPT))
    request.timeoutInterval = timeout
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else { throw ModelError.malformedResponse }
      return (data, http.statusCode)
    } catch let error as URLError {
      if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
      if error.code == .timedOut { throw ModelError.timedOut(.total) }
      throw ModelError.network(code: error.code.rawValue)
    }
  }
  var token = try await tokens.accessToken()
  var (data, status) = try await get(token)
  if status == 401 {
    await tokens.rejected(token)
    token = try await tokens.accessToken()
    (data, status) = try await get(token)
  }
  guard (200..<300).contains(status) else {
    throw chatGPTFailure(data, status: status, token: token)
  }
  return try decodeModelList(data, style: .chatGPT)
}
