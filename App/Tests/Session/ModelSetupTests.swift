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
