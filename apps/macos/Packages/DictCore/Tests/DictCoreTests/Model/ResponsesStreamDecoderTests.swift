// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

/// An SSE event of the Responses API, named like the real ones.
func responsesEvent(_ type: String, _ fields: JSONObject = [:]) -> String {
  var body = fields
  body["type"] = .string(type)
  return
    "event: \(type)\ndata: \(String(decoding: JSONValue.object(body).jsonData(), as: UTF8.self))\n\n"
}

let completedEvent = responsesEvent(
  "response.completed",
  ["response": ["status": "completed", "usage": ["input_tokens": 12, "output_tokens": 3]]])

struct ResponsesStreamDecoderTests {
  private func decode(_ stream: String) throws -> [StreamEvent] {
    var parser = SSEParser()
    var decoder = ResponsesStreamDecoder()
    var events: [StreamEvent] = []
    for event in parser.feed(Array(stream.utf8)) {
      events += try decoder.decode(event)
      if decoder.isDone { return events }
    }
    return events + (try decoder.finish())
  }

  @Test func textThinkingAndCompletion() throws {
    let stream =
      responsesEvent("response.created", ["response": ["status": "in_progress"]])
      + responsesEvent("response.reasoning_summary_text.delta", ["delta": "hm"])
      + responsesEvent("response.output_text.delta", ["delta": "你"])
      + responsesEvent("response.output_text.delta", ["delta": "好"])
      + completedEvent + responsesEvent("response.output_text.delta", ["delta": "late"])
    #expect(
      try decode(stream) == [
        .thinking, .text("你"), .text("好"),
        .finished(.complete, Usage(inputTokens: 12, outputTokens: 3)),
      ])
  }

  @Test func theTypeInTheDataIsEnoughWithoutAnEventLine() throws {
    let stream =
      #"data: {"type":"response.output_text.delta","delta":"a"}"# + "\n\n"
      + #"data: {"type":"response.completed","response":{}}"# + "\n\n"
    #expect(try decode(stream) == [.text("a"), .finished(.complete, nil)])
  }

  @Test func aCharacterSplitBetweenChunksDecodes() throws {
    let bytes = Array(responsesEvent("response.output_text.delta", ["delta": "狐"]).utf8)
    let cut = bytes.firstIndex(of: 0xE7).map { $0 + 1 } ?? 1
    var parser = SSEParser()
    var decoder = ResponsesStreamDecoder()
    let events = parser.feed(bytes[..<cut]) + parser.feed(bytes[cut...])
    #expect(try events.flatMap { try decoder.decode($0) } == [.text("狐")])
  }

  @Test func incompleteAndRefused() throws {
    let truncated = responsesEvent(
      "response.incomplete", ["response": ["incomplete_details": ["reason": "max_output_tokens"]]])
    #expect(try decode(truncated) == [.finished(.truncated, nil)])
    let filtered = responsesEvent(
      "response.incomplete", ["response": ["incomplete_details": ["reason": "content_filter"]]])
    #expect(try decode(filtered) == [.finished(.refused, nil)])
    let refusal =
      responsesEvent("response.refusal.delta", ["delta": "no"]) + completedEvent
    #expect(
      try decode(refusal) == [.finished(.refused, Usage(inputTokens: 12, outputTokens: 3))])
  }

  @Test func failuresInTheStreamAreThrown() throws {
    let limit = responsesEvent(
      "response.failed",
      ["response": ["error": ["code": "subscription_sharing_usage_limit_exceeded"]]])
    #expect(throws: ModelError.planLimitReached) { try decode(limit) }
    let unavailable = responsesEvent(
      "response.failed",
      ["response": ["error": ["code": "subscription_sharing_usage_unavailable"]]])
    #expect(throws: ModelError.server(status: 503)) { try decode(unavailable) }
    let error = responsesEvent("error", ["code": "server_error", "message": "boom"])
    #expect(throws: ModelError.server(status: 200)) { try decode(error) }
  }

  @Test func aStreamWithoutAFinalEvent() throws {
    let cut = responsesEvent("response.output_text.delta", ["delta": "部分"])
    #expect(try decode(cut) == [.text("部分"), .finished(.unknown, nil)])
    #expect(throws: ModelError.emptyResponse) { try decode("") }
    #expect(throws: ModelError.malformedResponse) { try decode("data: {oops\n\n") }
  }

  /// docs/reviews/chatgpt-login.md 2.7, one row each, as HTTP failures.
  @Test func httpFailuresMapByCodeFirst() {
    func failure(_ status: Int, _ body: String) -> ModelError {
      chatGPTFailure(Data(body.utf8), status: status, token: "tok-123")
    }
    func coded(_ code: String) -> String { #"{"error":{"code":"\#(code)","message":"m"}}"# }
    #expect(failure(403, coded("subscription_sharing_user_not_eligible")) == .planNotEligible)
    #expect(failure(429, coded("subscription_sharing_usage_limit_exceeded")) == .planLimitReached)
    #expect(failure(503, coded("subscription_sharing_usage_unavailable")) == .server(status: 503))
    #expect(failure(503, coded("subscription_sharing_user_unavailable")) == .server(status: 503))
    #expect(failure(401, coded("subscription_sharing_invalid_user")) == .unauthorized)
    #expect(failure(403, coded("chatpass_v2_scope_not_authorized")) == .planNotEligible)
    #expect(
      failure(403, coded("chatpass_v2_invalid_authorization_context")) == .planNotEligible)
    #expect(
      failure(403, coded("subscription_sharing_route_not_supported")) == .badRequest(message: "m"))
    #expect(
      failure(
        400,
        #"{"error":{"code":"subscription_sharing_unsupported_capability","message":"Unsupported parameter","param":"text.format"}}"#
      ) == .badRequest(message: "Unsupported parameter (text.format)"))
    #expect(failure(403, #"{"detail":"Not available in your region"}"#) == .planNotEligible)
    #expect(failure(401, #"{"detail":"Unauthorized"}"#) == .unauthorized)
    #expect(failure(404, coded("model_not_found")) == .modelNotFound)
    #expect(failure(429, coded("rate_limit_exceeded")) == .rateLimited(retryAfter: nil))
    #expect(
      failure(400, #"{"error":{"message":"bad tok-123"}}"#) == .badRequest(message: "bad ••••"))
    #expect(failure(502, "<html>") == .server(status: 502))
  }
}
