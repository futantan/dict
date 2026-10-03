// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

struct ModelEndpointTests {
  private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: try JSONEncoder().encode(value))
  }

  @Test(arguments: [AuthStyle.bearer, .header(name: "x-api-key"), .none])
  func authStyleRoundTrips(style: AuthStyle) throws {
    #expect(try roundTrip(style) == style)
  }

  @Test func endpointRoundTrips() throws {
    let endpoint = ModelEndpoint(
      providerID: "custom", baseURL: try #require(URL(string: "http://localhost:11434/v1")),
      model: "qwen3:4b", auth: .header(name: "x-api-key"), extraHeaders: ["X-Title": "Dict"],
      thinking: .lowest, jsonMode: .object, tokenLimitField: "max_tokens")

    #expect(try roundTrip(endpoint) == endpoint)
  }

  @Test func presetRoundTripsWithThinkingRuleFragments() throws {
    let preset = ProviderPreset(
      id: "openai", displayName: "OpenAI",
      baseURL: try #require(URL(string: "https://api.openai.com/v1")), auth: .bearer,
      requiresKey: true, keyHelpURL: nil, defaultModel: "gpt-6-luna", jsonMode: .schema,
      tokenLimitField: "max_completion_tokens",
      thinkingRules: [
        ThinkingRule(
          modelPrefix: "gpt-5-nano", off: nil,
          lowest: .object(["reasoning_effort": .string("minimal")]))
      ])

    #expect(try roundTrip(preset) == preset)
  }
}
