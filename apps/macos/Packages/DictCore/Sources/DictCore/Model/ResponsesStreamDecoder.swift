// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Turns the Responses API's SSE events into `StreamEvent`s (docs/reviews/chatgpt-login.md
/// 4.5). Only `response.completed` is a complete answer; events it does not know, such as
/// `response.created`, only feed the watchdog.
struct ResponsesStreamDecoder: Sendable {
  private var refused = false
  private var sawEvent = false
  /// True once a final event arrived; later events are ignored.
  private(set) var isDone = false

  init() {}

  mutating func decode(_ event: SSEEvent) throws -> [StreamEvent] {
    guard !isDone else { return [] }
    guard let body = try? JSONDecoder().decode(JSONValue.self, from: Data(event.data.utf8))
    else { throw ModelError.malformedResponse }
    sawEvent = true
    switch event.event ?? body["type"]?.stringValue ?? "" {
    case "response.output_text.delta":
      guard let delta = body["delta"]?.stringValue, !delta.isEmpty else { return [] }
      return [.text(delta)]
    case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
      return [.thinking]
    case "response.refusal.delta":
      refused = true
      return []
    case "response.completed":
      isDone = true
      return [.finished(refused ? .refused : .complete, Self.usage(body))]
    case "response.incomplete":
      isDone = true
      let reason: FinishReason =
        switch body["response"]?["incomplete_details"]?["reason"]?.stringValue {
        case "max_output_tokens": .truncated
        case "content_filter": .refused
        default: .unknown
        }
      return [.finished(reason, Self.usage(body))]
    case "response.failed":
      throw responsesError(status: nil, body["response"]?["error"] ?? .null)
    case "error":
      throw responsesError(status: nil, body["error"] ?? body)
    default:
      return []
    }
  }

  /// The stream closed before a final event: an interrupted answer, or no answer at all.
  func finish() throws -> [StreamEvent] {
    guard sawEvent else { throw ModelError.emptyResponse }
    return [.finished(.unknown, nil)]
  }

  private static func usage(_ body: JSONValue) -> Usage? {
    guard let usage = body["response"]?["usage"] else { return nil }
    return Usage(
      inputTokens: usage["input_tokens"]?.intValue ?? 0,
      outputTokens: usage["output_tokens"]?.intValue ?? 0)
  }
}

/// Maps a ChatGPT-plan error, from an HTTP status (nil inside a stream) and the error object
/// (`error`, or the `{"detail": …}` of an admission failure), by its `code` first
/// (docs/reviews/chatgpt-login.md 2.7).
func responsesError(status: Int?, _ error: JSONValue) -> ModelError {
  let code = error["code"]?.stringValue ?? ""
  var message = errorMessage(error)
  if message.isEmpty { message = error["detail"].map(errorMessage) ?? code }
  if let param = error["param"]?.stringValue, !param.isEmpty {
    message += " (\(param))"
  }
  switch code {
  case "subscription_sharing_usage_limit_exceeded":
    return .planLimitReached
  case "subscription_sharing_user_not_eligible", "chatpass_v2_scope_not_authorized",
    "chatpass_v2_invalid_authorization_context":
    return .planNotEligible
  case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable":
    return .server(status: 503)
  case "subscription_sharing_invalid_user":
    return .unauthorized
  case "subscription_sharing_unsupported_capability", "subscription_sharing_route_not_supported":
    return .badRequest(message: message)
  default:
    break
  }
  switch status {
  case 403?: return .planNotEligible
  case let status?: return modelError(status: status, message: message, retryAfter: nil)
  case nil where code.contains("rate_limit"): return .rateLimited(retryAfter: nil)
  case nil: return .server(status: 200)
  }
}
