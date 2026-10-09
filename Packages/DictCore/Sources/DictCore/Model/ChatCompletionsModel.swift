// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Synchronization

/// Optional request parameters a provider rejected, remembered per endpoint and model so
/// later calls leave them out (architecture 6.4).
public final class DroppedParameters: Sendable {
  public static let shared = DroppedParameters()

  private let names = Mutex<[String: Set<String>]>([:])

  public init() {}

  func names(for endpoint: ModelEndpoint) -> Set<String> {
    names.withLock { $0[Self.key(endpoint)] ?? [] }
  }

  func add(_ name: String, for endpoint: ModelEndpoint) {
    names.withLock { _ = $0[Self.key(endpoint), default: []].insert(name) }
  }

  private static func key(_ endpoint: ModelEndpoint) -> String {
    "\(endpoint.baseURL.absoluteString) \(endpoint.model)"
  }
}

/// A `TextModel` for any OpenAI-compatible Chat Completions endpoint (architecture 6.1–6.4).
public struct ChatCompletionsModel: TextModel {
  public let endpoint: ModelEndpoint
  public let rules: [ThinkingRule]
  private let apiKey: String?
  private let session: URLSession
  private let makeWatchdog: @Sendable () -> any ModelWatchdog
  private let timeouts: ModelTimeouts
  private let dropped: DroppedParameters

  /// - Parameters:
  ///   - rules: the thinking rules of the endpoint's preset.
  ///   - apiKey: nil or empty when the endpoint needs none.
  public init(
    endpoint: ModelEndpoint, rules: [ThinkingRule], apiKey: String?,
    session: URLSession = .shared, clock: some Clock<Duration> = ContinuousClock(),
    timeouts: ModelTimeouts = .standard, dropped: DroppedParameters = .shared
  ) {
    self.endpoint = endpoint
    self.rules = rules
    self.apiKey = apiKey
    self.session = session
    self.makeWatchdog = { Watchdog(clock: clock, timeouts: timeouts) }
    self.timeouts = timeouts
    self.dropped = dropped
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

  /// Races the exchange against the watchdog; whichever ends first cancels the other.
  private func run(
    _ request: ModelRequest, yield: @escaping @Sendable (StreamEvent) -> Void
  ) async throws {
    if endpoint.auth != .none && (apiKey ?? "").isEmpty { throw ModelError.missingKey }
    let watchdog = makeWatchdog()
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { try await exchange(request, watchdog: watchdog, yield: yield) }
      group.addTask { throw ModelError.timedOut(try await watchdog.expiry()) }
      defer { group.cancelAll() }
      try await group.next()
    }
  }

  private func exchange(
    _ request: ModelRequest, watchdog: any ModelWatchdog,
    yield: @Sendable (StreamEvent) -> Void
  ) async throws {
    do {
      var body = requestBody(request, endpoint: endpoint, rules: rules)
      for name in dropped.names(for: endpoint) { body = removing(name, from: body) }
      var (bytes, response) = try await send(body)

      if response.statusCode == 400 {
        let failure = try await readFailure(bytes, response)
        guard let name = droppableParameter(failure, in: body) else { throw failure.error }
        dropped.add(name, for: endpoint)
        (bytes, response) = try await send(removing(name, from: body))
      }
      guard (200..<300).contains(response.statusCode) else {
        throw try await readFailure(bytes, response).error
      }

      var decoder = ChatStreamDecoder()
      let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? ""
      guard contentType.lowercased().hasPrefix("text/event-stream") else {
        watchdog.feed()
        try decoder.decodeComplete(try await collect(bytes)).forEach(yield)
        return
      }
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

  private func send(_ body: JSONValue) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
    var request = URLRequest(url: endpoint.baseURL.appending(path: "chat/completions"))
    request.httpMethod = "POST"
    // Longer than the watchdog, so the watchdog reports a stalled stream first.
    request.timeoutInterval = Double(timeouts.total.components.seconds) + 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    endpoint.authorize(&request, apiKey: apiKey)
    request.httpBody = try JSONEncoder().encode(body)
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse else { throw ModelError.malformedResponse }
    return (bytes, http)
  }

  /// Reads an error response and maps it, with the key masked in the message.
  private func readFailure(
    _ bytes: URLSession.AsyncBytes, _ response: HTTPURLResponse
  ) async throws -> (error: ModelError, param: String?) {
    httpFailure(try await collect(bytes, limit: 64 * 1024), response, apiKey: apiKey)
  }

  /// The optional parameter a 400 complains about, when leaving it out may help.
  private func droppableParameter(
    _ failure: (error: ModelError, param: String?), in body: JSONValue
  ) -> String? {
    guard case .badRequest(let message) = failure.error else { return nil }
    var candidates = ["response_format", "stream_options", endpoint.tokenLimitField]
    if case .object(let fragment) = thinkingFragment(
      for: endpoint.model, setting: endpoint.thinking, rules: rules)
    {
      candidates += fragment.keys.sorted()
    }
    let present = candidates.filter { body[$0] != nil }
    if let param = failure.param, present.contains(param) { return param }
    return present.first { message.contains($0) }
  }

  private func collect(_ bytes: URLSession.AsyncBytes, limit: Int = 4 * 1024 * 1024)
    async throws -> Data
  {
    var data = Data()
    for try await byte in bytes {
      data.append(byte)
      if data.count >= limit { break }
    }
    return data
  }
}

extension ModelEndpoint {
  /// Adds the extra headers and the key, as the endpoint's auth style says.
  func authorize(_ request: inout URLRequest, apiKey: String?) {
    for (name, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
    guard let apiKey, !apiKey.isEmpty else { return }
    switch auth {
    case .bearer: request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    case .header(let name): request.setValue(apiKey, forHTTPHeaderField: name)
    case .none: break
    }
  }
}

/// Maps a failed response and its body, with the key masked in the message. `param` is the
/// parameter an OpenAI-style error names, if any.
func httpFailure(
  _ data: Data, _ response: HTTPURLResponse, apiKey: String?
) -> (error: ModelError, param: String?) {
  let json = try? JSONDecoder().decode(JSONValue.self, from: data)
  var message = json.map { errorMessage($0["error"] ?? $0) } ?? ""
  if message.isEmpty { message = String(decoding: data, as: UTF8.self) }
  if let apiKey, !apiKey.isEmpty {
    message = message.replacingOccurrences(of: apiKey, with: "••••")
  }
  let error = modelError(
    status: response.statusCode, message: message, retryAfter: retryAfter(response))
  return (error, json?["error"]?["param"]?.stringValue)
}

/// The value of `Retry-After` (seconds) or `retry-after-ms`.
private func retryAfter(_ response: HTTPURLResponse) -> Duration? {
  if let ms = response.value(forHTTPHeaderField: "retry-after-ms").flatMap(Double.init) {
    return .milliseconds(ms)
  }
  return response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init).map {
    .seconds($0)
  }
}

private func removing(_ name: String, from body: JSONValue) -> JSONValue {
  guard case .object(var members) = body else { return body }
  members[name] = nil
  return .object(members)
}
