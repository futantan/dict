// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

struct ModelPreferencesTests {
  private let presets: [ProviderPreset]

  init() throws {
    presets = try ProviderPreset.all()
  }

  private func preset(_ id: String) throws -> ProviderPreset {
    try #require(presets.first { $0.id == id })
  }

  private func configuration(
    _ preferences: ModelPreferences, hasKey: Bool
  ) -> Result<ModelConfiguration, ModelSetupIssue> {
    Result { () throws(ModelSetupIssue) in
      try preferences.configuration(presets: presets, hasKey: hasKey)
    }
  }

  // MARK: - Endpoints

  @Test func openAIUsesThePresetWithBearerAuthAndDefaultModel() throws {
    let openAI = try preset("openai")
    let result = try configuration(ModelPreferences(providerID: "openai"), hasKey: true).get()

    #expect(result.endpoint == openAI.endpoint())
    #expect(result.endpoint.auth == .bearer)
    #expect(result.endpoint.model == "gpt-6-luna")
    #expect(result.endpoint.thinking == .off)
    #expect(result.rules == openAI.thinkingRules)
  }

  @Test func openAITakesTheModelAndBaseURLOverrides() throws {
    let preferences = ModelPreferences(
      providerID: "openai", model: "  gpt-5-nano ", baseURL: " https://proxy.example.com/v1 ")

    let endpoint = try configuration(preferences, hasKey: true).get().endpoint

    #expect(endpoint.model == "gpt-5-nano")
    #expect(endpoint.baseURL == URL(string: "https://proxy.example.com/v1"))
    #expect(endpoint.tokenLimitField == "max_completion_tokens")
  }

  @Test func openAIWithoutKeyIsMissingKey() {
    #expect(
      configuration(ModelPreferences(providerID: "openai"), hasKey: false) == .failure(.missingKey))
  }

  @Test func ollamaNeedsNoKeyButNeedsAModel() throws {
    #expect(
      configuration(ModelPreferences(providerID: "ollama"), hasKey: false)
        == .failure(.missingModel))

    let endpoint = try configuration(
      ModelPreferences(providerID: "ollama", model: "qwen3:4b"), hasKey: false
    ).get().endpoint

    #expect(endpoint.auth == .none)
    #expect(endpoint.baseURL == URL(string: "http://localhost:11434/v1"))
    #expect(endpoint.tokenLimitField == "max_tokens")
  }

  @Test func ollamaIgnoresAStoredKey() throws {
    let endpoint = try configuration(
      ModelPreferences(providerID: "ollama", model: "qwen3:4b"), hasKey: true
    ).get().endpoint

    #expect(endpoint.auth == .none)
  }

  @Test func customWithKeyUsesBearer() throws {
    let preferences = ModelPreferences(
      providerID: "custom", model: "deepseek-chat", baseURL: "https://api.deepseek.com/v1")

    let endpoint = try configuration(preferences, hasKey: true).get().endpoint

    #expect(endpoint.providerID == "custom")
    #expect(endpoint.auth == .bearer)
    #expect(endpoint.baseURL == URL(string: "https://api.deepseek.com/v1"))
    #expect(endpoint.model == "deepseek-chat")
  }

  /// A custom service without a key must be built with `.none`, or the client fails with
  /// `.missingKey` (the M1.2 convention).
  @Test func customWithoutKeyUsesNoAuth() throws {
    let preferences = ModelPreferences(
      providerID: "custom", model: "llama3", baseURL: "http://127.0.0.1:8080/v1")

    let endpoint = try configuration(preferences, hasKey: false).get().endpoint

    #expect(endpoint.auth == .none)
  }

  @Test func customNeedsItsOwnBaseURLAndModel() {
    #expect(
      configuration(ModelPreferences(providerID: "custom", model: "m"), hasKey: true)
        == .failure(.missingBaseURL))
    #expect(
      configuration(
        ModelPreferences(providerID: "custom", baseURL: "https://api.example.org/v1"), hasKey: true)
        == .failure(.missingModel))
  }

  @Test func noProviderAndUnknownProvider() {
    #expect(configuration(ModelPreferences(), hasKey: true) == .failure(.noProvider))
    #expect(
      configuration(ModelPreferences(providerID: "acme", model: "m"), hasKey: true)
        == .failure(.unknownProvider))
  }

  @Test func baseURLProblemsComeBeforeAMissingKey() {
    let preferences = ModelPreferences(providerID: "openai", baseURL: "http://api.example.com/v1")

    #expect(configuration(preferences, hasKey: false) == .failure(.insecureBaseURL))
  }

  // MARK: - Custom options

  @Test func customOptionsOverrideThePreset() throws {
    var preferences = ModelPreferences(
      providerID: "custom", model: "deepseek-chat", baseURL: "https://api.deepseek.com/v1")
    preferences.thinking = .providerDefault
    preferences.tokenLimitField = "max_completion_tokens"
    preferences.jsonMode = .object

    let endpoint = try configuration(preferences, hasKey: true).get().endpoint

    #expect(endpoint.thinking == .providerDefault)
    #expect(endpoint.tokenLimitField == "max_completion_tokens")
    #expect(endpoint.jsonMode == .object)
  }

  @Test func customOptionsDefaultToThePreset() throws {
    let custom = try preset("custom")
    let preferences = ModelPreferences(
      providerID: "custom", model: "m", baseURL: "https://api.example.org/v1")

    let endpoint = try configuration(preferences, hasKey: false).get().endpoint

    #expect(endpoint.thinking == .off)
    #expect(endpoint.tokenLimitField == custom.tokenLimitField)
    #expect(endpoint.jsonMode == custom.jsonMode)
  }

  /// The options belong to the custom provider; presets keep their tested values.
  @Test func presetsIgnoreCustomOptions() throws {
    var preferences = ModelPreferences(providerID: "openai")
    preferences.thinking = .providerDefault
    preferences.tokenLimitField = "max_tokens"
    preferences.jsonMode = JSONMode.none

    #expect(
      try configuration(preferences, hasKey: true).get().endpoint == preset("openai").endpoint())
  }

  @Test func preferencesWithoutOptionsDecode() throws {
    let json = #"{"providerID":"custom","model":"m","baseURL":"https://a.example/v1"}"#
    let decoded = try JSONDecoder().decode(ModelPreferences.self, from: Data(json.utf8))

    #expect(
      decoded
        == ModelPreferences(providerID: "custom", model: "m", baseURL: "https://a.example/v1"))
    #expect(decoded.thinking == nil && decoded.tokenLimitField == nil && decoded.jsonMode == nil)
  }

  @Test func optionsRoundTrip() throws {
    var preferences = ModelPreferences(providerID: "custom")
    preferences.thinking = .lowest
    preferences.tokenLimitField = "max_tokens"
    preferences.jsonMode = JSONMode.none

    let data = try JSONEncoder().encode(preferences)

    #expect(try JSONDecoder().decode(ModelPreferences.self, from: data) == preferences)
  }

  // MARK: - Model list endpoint

  /// Listing is how the user finds a model name, so it must work before one is typed.
  @Test func listEndpointNeedsNoModel() throws {
    let endpoint = try listEndpoint(ModelPreferences(providerID: "ollama"), hasKey: false).get()

    #expect(endpoint.baseURL == URL(string: "http://localhost:11434/v1"))
    #expect(endpoint.auth == .none)
  }

  @Test func listEndpointStillChecksTheURLAndKey() {
    #expect(
      listEndpoint(ModelPreferences(providerID: "custom"), hasKey: false)
        == .failure(.missingBaseURL))
    #expect(
      listEndpoint(ModelPreferences(providerID: "openai"), hasKey: false) == .failure(.missingKey))
    #expect(listEndpoint(ModelPreferences(), hasKey: true) == .failure(.noProvider))
  }

  private func listEndpoint(
    _ preferences: ModelPreferences, hasKey: Bool
  ) -> Result<ModelEndpoint, ModelSetupIssue> {
    Result { () throws(ModelSetupIssue) in
      try preferences.listEndpoint(presets: presets, hasKey: hasKey)
    }
  }

  // MARK: - Base URL validation

  private func validate(_ text: String) -> Result<URL, ModelSetupIssue> {
    Result { () throws(ModelSetupIssue) in try validatedBaseURL(text) }
  }

  @Test(arguments: [
    "https://api.openai.com/v1",
    "https://openrouter.ai/api/v1",
    "http://localhost:11434/v1",
    "http://LOCALHOST:1234/v1",
    "http://127.0.0.1:8080/v1",
    "http://127.1.2.3/v1",
    "http://[::1]:8080/v1",
  ])
  func acceptsHTTPSAndLoopbackHTTP(text: String) {
    #expect(validate(text).map(\.absoluteString) == .success(text))
  }

  @Test func trimsWhitespace() {
    #expect(
      validate("  https://api.example.org/v1\n").map(\.absoluteString)
        == .success("https://api.example.org/v1"))
  }

  @Test(arguments: [
    "http://api.example.com/v1",
    "http://192.168.1.20:11434/v1",
    "http://localhost.example.com/v1",
    "http://127.example.com/v1",
  ])
  func rejectsPlainHTTPToOtherHosts(text: String) {
    #expect(validate(text) == .failure(.insecureBaseURL))
  }

  @Test(arguments: [
    "api.openai.com/v1", "ftp://example.com", "https://", "not a url", "https:///v1",
  ])
  func rejectsMalformedURLs(text: String) {
    #expect(validate(text) == .failure(.invalidBaseURL))
  }

  @Test func rejectsEmptyText() {
    #expect(validate("   ") == .failure(.missingBaseURL))
  }
}
