// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

/// The bytes sent to the ChatGPT plan's Responses API.
struct ResponsesBodyTests {
  private func rules() throws -> [ThinkingRule] {
    try #require(try ProviderPreset.all().first { $0.id == "chatgpt" }).thinkingRules
  }

  private func snapshot(
    _ request: ModelRequest, model: String = "gpt-6.1-sol", thinking: ThinkingSetting = .off
  ) throws -> String {
    let body = responsesBody(request, model: model, thinking: thinking, rules: try rules())
    return String(decoding: body.jsonData(), as: UTF8.self)
  }

  @Test func translation() throws {
    let request = ModelRequest(system: "SYS", user: "USER", output: .text, maxOutputTokens: 256)
    #expect(
      try snapshot(request)
        == #"{"model":"gpt-6.1-sol","instructions":"SYS","input":[{"role":"user","content":"USER"}],"#
        + #""store":false,"stream":true,"reasoning":{"effort":"none"}}"#)
  }

  @Test func strictSchemaGoesInTextFormat() throws {
    let request = ModelRequest(
      system: "", user: "USER", output: .jsonSchema(name: "card", schema: ["type": "object"]),
      maxOutputTokens: 800)
    #expect(
      try snapshot(request, model: "o9", thinking: .lowest)
        == #"{"model":"o9","input":[{"role":"user","content":"USER"}],"store":false,"stream":true,"#
        + #""reasoning":{"effort":"minimal"},"#
        + #""text":{"format":{"type":"json_schema","name":"card","strict":true,"schema":{"type":"object"}}}}"#
    )
  }

  @Test func neverSendsWhatThePlanRejects() throws {
    let request = ModelRequest(system: "SYS", user: "USER", output: .text, maxOutputTokens: 256)
    let body = responsesBody(
      request, model: "gpt-6.1-sol", thinking: .providerDefault, rules: try rules())
    for name in [
      "max_output_tokens", "temperature", "top_p", "metadata", "user", "truncation",
      "previous_response_id", "prompt_cache_retention", "safety_identifier", "messages",
      "reasoning",
    ] {
      #expect(body[name] == nil, "\(name)")
    }
    let roles = body["input"]?.arrayValue?.compactMap { $0["role"]?.stringValue }
    #expect(roles == ["user"])
  }
}
