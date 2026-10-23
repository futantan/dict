// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Testing

@testable import DictApp

/// Fails every read, like a locked keychain.
private struct BrokenStore: SecretStore {
  func secret(for account: String) throws(KeychainError) -> String? {
    throw KeychainError(status: -25308)
  }
  func setSecret(_ secret: String?, for account: String) throws(KeychainError) {}
}

struct ModelSetupTests {
  private let presets = (try? ProviderPreset.all()) ?? []
  private let openAI = ModelPreferences(providerID: "openai")

  @Test func noProviderMeansNoModel() {
    #expect(
      configuredModel(ModelPreferences(), presets: presets, secrets: InMemorySecretStore()) == nil)
  }

  @Test func aSavedKeyMakesTheModel() throws {
    let model = try #require(
      configuredModel(
        openAI, presets: presets, secrets: InMemorySecretStore(["openai": " sk-test "])))
    #expect(model.apiKey == "sk-test")
    #expect(model.configuration.endpoint.providerID == "openai")
    #expect(!model.configuration.endpoint.model.isEmpty)
  }

  @Test func withoutTheRequiredKeyThereIsNoModel() {
    #expect(configuredModel(openAI, presets: presets, secrets: InMemorySecretStore()) == nil)
    #expect(
      configuredModel(openAI, presets: presets, secrets: InMemorySecretStore(["openai": "  "]))
        == nil)
  }

  @Test func aKeychainFailureFallsBackToNoModel() {
    #expect(configuredModel(openAI, presets: presets, secrets: BrokenStore()) == nil)
  }
}

/// Fails the test on any read: the mock model must never touch the Keychain.
private struct UntouchableStore: SecretStore {
  func secret(for account: String) throws(KeychainError) -> String? {
    Issue.record("read the key for \(account)")
    return nil
  }
  func setSecret(_ secret: String?, for account: String) throws(KeychainError) {
    Issue.record("wrote the key for \(account)")
  }
}

struct MockModelSetupTests {
  private let presets = (try? ProviderPreset.all()) ?? []
  private let mock = ["DICT_MOCK_MODEL": "http://127.0.0.1:8767/v1"]

  @Test func theVariableOverridesThePreferencesWithoutTheKeychain() throws {
    let model = try #require(
      configuredModel(
        ModelPreferences(providerID: "openai"), presets: presets, secrets: UntouchableStore(),
        environment: mock))
    #expect(model.configuration.endpoint.baseURL.absoluteString == "http://127.0.0.1:8767/v1")
    #expect(model.configuration.endpoint.providerID == ProviderPreset.customID)
    #expect(model.configuration.endpoint.model == "mock")
    #expect(model.apiKey == "mock")
  }

  @Test func itWorksWithNoModelSaved() {
    #expect(
      configuredModel(
        ModelPreferences(), presets: presets, secrets: UntouchableStore(), environment: mock)
        != nil)
  }

  @Test func aURLOffThisMacIsRefusedRatherThanFallingBackToTheRealModel() {
    #expect(
      configuredModel(
        ModelPreferences(providerID: "openai"), presets: presets, secrets: UntouchableStore(),
        environment: ["DICT_MOCK_MODEL": "http://example.com/v1"]) == nil)
  }

  @Test func anEmptyVariableIsIgnored() {
    #expect(mockModelBaseURL(["DICT_MOCK_MODEL": " "]) == nil)
    #expect(mockModelBaseURL([:]) == nil)
    #expect(mockModelBaseURL(mock) == "http://127.0.0.1:8767/v1")
  }
}
