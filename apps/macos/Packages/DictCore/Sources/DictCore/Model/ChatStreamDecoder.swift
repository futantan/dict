// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Turns Chat Completions SSE events, or one non-streamed response, into `StreamEvent`s
/// (architecture 6.3).
struct ChatStreamDecoder: Sendable {
  private var filter = ThinkFilter()
  private var finishReason: FinishReason?
  private var refused = false
  private var usage: Usage?
  private var sawChunk = false
  /// True once `[DONE]` arrived; later events are ignored.
  private(set) var isDone = false

  init() {}

  mutating func decode(_ event: SSEEvent) throws -> [StreamEvent] {
    guard !isDone else { return [] }
    if event.data.trimmingCharacters(in: .whitespaces) == "[DONE]" {
      isDone = true
      return try finish()
    }
    let body = try Self.decodeJSON(Data(event.data.utf8))
    if event.event == "error" || body.error != nil {
      throw streamError(body.error ?? .null)
    }
    return absorb(body, isStreamed: true)
  }

  /// Ends the stream: flushes held-back text and reports how it ended.
  mutating func finish() throws -> [StreamEvent] {
    guard sawChunk else { throw ModelError.emptyResponse }
    let reason = refused ? .refused : (finishReason ?? .unknown)
    return filter.finish() + [.finished(reason, usage)]
  }

  /// Decodes a complete, non-streamed response.
  mutating func decodeComplete(_ data: Data) throws -> [StreamEvent] {
    guard !data.isEmpty else { throw ModelError.emptyResponse }
    let body = try Self.decodeJSON(data)
    if let error = body.error { throw streamError(error) }
    let events = absorb(body, isStreamed: false)
    return events + (try finish())
  }

  private mutating func absorb(_ body: Body, isStreamed: Bool) -> [StreamEvent] {
    sawChunk = true
    if let tokens = body.usage {
      usage = Usage(
        inputTokens: tokens.promptTokens ?? 0, outputTokens: tokens.completionTokens ?? 0)
    }
    var events: [StreamEvent] = []
    for choice in body.choices ?? [] {
      if let reason = choice.finishReason { finishReason = Self.finishReason(reason) }
      guard let message = isStreamed ? choice.delta : choice.message else { continue }
      if !(message.reasoning ?? message.reasoningContent ?? "").isEmpty {
        events.append(.thinking)
      }
      if !(message.refusal ?? "").isEmpty { refused = true }
      if let content = message.content, !content.isEmpty {
        events += filter.push(content)
      }
    }
    return events
  }

  private static func finishReason(_ raw: String) -> FinishReason {
    switch raw {
    case "stop": .complete
    case "length": .truncated
    case "content_filter": .refused
    default: .unknown
    }
  }

  private static func decodeJSON(_ data: Data) throws -> Body {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    do {
      return try decoder.decode(Body.self, from: data)
    } catch {
      throw ModelError.malformedResponse
    }
  }

  /// A chunk of a streamed response, or a whole non-streamed response.
  private struct Body: Decodable {
    struct Choice: Decodable {
      var delta: Message?
      var message: Message?
      var finishReason: String?
    }
    struct Message: Decodable {
      var content: String?
      var reasoning: String?
      var reasoningContent: String?
      var refusal: String?
    }
    struct Tokens: Decodable {
      var promptTokens: Int?
      var completionTokens: Int?
    }
    var choices: [Choice]?
    var usage: Tokens?
    var error: JSONValue?
  }
}

/// Maps an `error` member that arrived inside an HTTP 200 response.
private func streamError(_ error: JSONValue) -> ModelError {
  if let status = error["code"]?.intValue ?? error["status"]?.intValue {
    return modelError(status: status, message: errorMessage(error), retryAfter: nil)
  }
  if error["code"]?.stringValue?.contains("rate_limit") == true {
    return .rateLimited(retryAfter: nil)
  }
  return .server(status: 200)
}

/// Maps a failed HTTP status (architecture 6.3).
func modelError(status: Int, message: String, retryAfter: Duration?) -> ModelError {
  switch status {
  case 401, 403: .unauthorized
  case 404: .modelNotFound
  case 429: .rateLimited(retryAfter: retryAfter)
  case 400..<500: .badRequest(message: message)
  default: .server(status: status)
  }
}

/// The human-readable message of a provider error object or string.
func errorMessage(_ error: JSONValue) -> String {
  error["message"]?.stringValue ?? error.stringValue ?? ""
}
