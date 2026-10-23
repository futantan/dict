// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

/// The snapshots are the bytes sent on the wire (`JSONValue.jsonData`), so they also pin the
/// order of every object: providers with strict structured output write the answer's keys in
/// the order of the schema's `properties`.
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
    return String(decoding: body.jsonData(), as: UTF8.self)
  }

  private let messages =
    #""messages":[{"role":"system","content":"SYS"},{"role":"user","content":"USER"}]"#
  private let streaming = #""stream":true,"stream_options":{"include_usage":true}"#
  private let strictCard =
    #""response_format":{"type":"json_schema","json_schema":{"name":"card","strict":true,"#
    + #""schema":{"type":"object"}}}"#

  @Test func openAITranslation() throws {
    #expect(
      try snapshot(translate, "openai")
        == #"{"model":"gpt-6-luna",\#(messages),\#(streaming),"#
        + #""max_completion_tokens":256,"reasoning_effort":"none"}"#)
  }

  @Test func openAICardUsesStrictSchema() throws {
    #expect(
      try snapshot(card, "openai")
        == #"{"model":"gpt-6-luna",\#(messages),\#(streaming),"#
        + #""max_completion_tokens":800,"reasoning_effort":"none",\#(strictCard)}"#)
  }

  @Test func gpt5NanoFallsBackToMinimal() throws {
    #expect(
      try snapshot(translate, "openai", model: "gpt-5-nano")
        == #"{"model":"gpt-5-nano",\#(messages),\#(streaming),"#
        + #""max_completion_tokens":256,"reasoning_effort":"minimal"}"#)
  }

  @Test func ollamaUsesMaxTokensAndNone() throws {
    #expect(
      try snapshot(card, "ollama", model: "qwen3:4b", thinking: .lowest)
        == #"{"model":"qwen3:4b",\#(messages),\#(streaming),"#
        + #""max_tokens":800,"reasoning_effort":"none",\#(strictCard)}"#)
  }

  @Test func customJSONObjectModeAndProviderDefaultThinking() throws {
    #expect(
      try snapshot(
        card, "custom", model: "deepseek-chat", thinking: .providerDefault, jsonMode: .object)
        == #"{"model":"deepseek-chat",\#(messages),\#(streaming),"#
        + #""max_tokens":800,"response_format":{"type":"json_object"}}"#)
  }

  @Test func customLowestAndNoJSONMode() throws {
    #expect(
      try snapshot(card, "custom", model: "m", thinking: .lowest, jsonMode: JSONMode.none)
        == #"{"model":"m",\#(messages),\#(streaming),"#
        + #""max_tokens":800,"reasoning_effort":"minimal"}"#)
  }

  /// Where each of `keys` first occurs in `text` as an object key, after `start`.
  private func offsets(of keys: [String], in text: String, after start: String) throws -> [Int] {
    let from = try #require(text.range(of: start)).upperBound
    return try keys.map { key in
      let found = try #require(text.range(of: "\"\(key)\":", range: from..<text.endIndex))
      return text.distance(from: text.startIndex, to: found.lowerBound)
    }
  }

  @Test func cardSchemaKeysGoOutInDeclarationOrder() throws {
    let request = PromptBuilder.card(
      term: "ran", context: "She ran a bakery.", pair: LanguagePair(), accent: .american,
      nonce: "0a1b2c3d")
    let text = try snapshot(request, "openai")
    let fields = [
      "status", "lemma", "phonetic", "partOfSpeech", "definition", "contextTranslation",
      "otherSenses", "examples", "collocations", "level",
    ]
    let top = try offsets(of: fields, in: text, after: #""schema":{"#)
    #expect(top == top.sorted())
    let example = try offsets(of: ["sentence", "translation"], in: text, after: #""examples":"#)
    #expect(example == example.sorted())
    #expect(text.contains(#""required":["\#(fields.joined(separator: #"",""#))"]"#))
    #expect(try snapshot(request, "openai") == text)
  }

  @Test func proofreadSchemaKeysGoOutInDeclarationOrder() throws {
    let text = try snapshot(PromptBuilder.proofread("Hi", nonce: "0a1b2c3d"), "openai")
    let edit = try offsets(of: ["kind", "wrong", "right"], in: text, after: #""items":{"#)
    #expect(edit == edit.sorted())
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
