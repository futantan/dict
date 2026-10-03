// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

struct RequestBodyTests {
  private let translate = ModelRequest(
    system: "SYS", user: "USER", output: .text, maxOutputTokens: 256)
  private let card = ModelRequest(
    system: "SYS", user: "USER",
    output: .jsonSchema(name: "card", schema: ["type": "object"]), maxOutputTokens: 800)

  private func preset(_ id: String) throws -> ProviderPreset {
    try #require(try ProviderPreset.all().first { $0.id == id })
  }

  private func snapshot(
    _ request: ModelRequest, _ presetID: String, model: String? = nil,
    thinking: ThinkingSetting = .off, jsonMode: JSONMode? = nil
  ) throws -> String {
    let preset = try preset(presetID)
    var endpoint = preset.endpoint(model: model, thinking: thinking)
    if let jsonMode { endpoint.jsonMode = jsonMode }
    let body = requestBody(request, endpoint: endpoint, rules: preset.thinkingRules)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(body), as: UTF8.self)
  }

  private let messages =
    #""messages":[{"content":"SYS","role":"system"},{"content":"USER","role":"user"}]"#

  @Test func openAITranslation() throws {
    #expect(
      try snapshot(translate, "openai")
        == #"{"max_completion_tokens":256,\#(messages),"model":"gpt-6-luna","#
        + #""reasoning_effort":"none","stream":true,"stream_options":{"include_usage":true}}"#)
  }

  @Test func openAICardUsesStrictSchema() throws {
    #expect(
      try snapshot(card, "openai")
        == #"{"max_completion_tokens":800,\#(messages),"model":"gpt-6-luna","#
        + #""reasoning_effort":"none","response_format":{"json_schema":{"name":"card","#
        + #""schema":{"type":"object"},"strict":true},"type":"json_schema"},"#
        + #""stream":true,"stream_options":{"include_usage":true}}"#)
  }

  @Test func gpt5NanoFallsBackToMinimal() throws {
    #expect(
      try snapshot(translate, "openai", model: "gpt-5-nano")
        == #"{"max_completion_tokens":256,\#(messages),"model":"gpt-5-nano","#
        + #""reasoning_effort":"minimal","stream":true,"stream_options":{"include_usage":true}}"#)
  }

  @Test func ollamaUsesMaxTokensAndNone() throws {
    #expect(
      try snapshot(card, "ollama", model: "qwen3:4b", thinking: .lowest)
        == #"{"max_tokens":800,\#(messages),"model":"qwen3:4b","reasoning_effort":"none","#
        + #""response_format":{"json_schema":{"name":"card","schema":{"type":"object"},"#
        + #""strict":true},"type":"json_schema"},"stream":true,"#
        + #""stream_options":{"include_usage":true}}"#)
  }

  @Test func customJSONObjectModeAndProviderDefaultThinking() throws {
    #expect(
      try snapshot(
        card, "custom", model: "deepseek-chat", thinking: .providerDefault, jsonMode: .object)
        == #"{"max_tokens":800,\#(messages),"model":"deepseek-chat","#
        + #""response_format":{"type":"json_object"},"stream":true,"#
        + #""stream_options":{"include_usage":true}}"#)
  }

  @Test func customLowestAndNoJSONMode() throws {
    #expect(
      try snapshot(card, "custom", model: "m", thinking: .lowest, jsonMode: JSONMode.none)
        == #"{"max_tokens":800,\#(messages),"model":"m","reasoning_effort":"minimal","#
        + #""stream":true,"stream_options":{"include_usage":true}}"#)
  }

  @Test func emptySystemIsOmitted() throws {
    let request = ModelRequest(system: "", user: "U", output: .text, maxOutputTokens: 1)
    let endpoint = try preset("openai").endpoint()
    let body = requestBody(request, endpoint: endpoint, rules: [])
    #expect(body["messages"] == [["role": "user", "content": "U"]])
    #expect(body["reasoning_effort"] == nil)
  }
}

struct ProviderPresetTests {
  @Test func tableHasTheThreeV1Rows() throws {
    let presets = try ProviderPreset.all()
    #expect(presets.map(\.id) == ["openai", "ollama", ProviderPreset.customID])
    let openAI = try #require(presets.first)
    #expect(openAI.baseURL.absoluteString == "https://api.openai.com/v1")
    #expect(openAI.requiresKey && openAI.auth == .bearer)
    #expect(presets[1].auth == AuthStyle.none && !presets[1].requiresKey)
  }

  @Test func longestPrefixWins() {
    let rules = [
      ThinkingRule(modelPrefix: "", off: "a", lowest: "b"),
      ThinkingRule(modelPrefix: "x-1", off: "c", lowest: nil),
      ThinkingRule(modelPrefix: "x", off: "d", lowest: "e"),
    ]
    #expect(thinkingFragment(for: "x-1-mini", setting: .off, rules: rules) == "c")
    #expect(thinkingFragment(for: "x-1-mini", setting: .lowest, rules: rules) == "c")
    #expect(thinkingFragment(for: "x-2", setting: .lowest, rules: rules) == "e")
    #expect(thinkingFragment(for: "y", setting: .off, rules: rules) == "a")
    #expect(thinkingFragment(for: "y", setting: .providerDefault, rules: rules) == nil)
    #expect(thinkingFragment(for: "y", setting: .off, rules: []) == nil)
  }
}
