// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// The model to translate with, from the saved preferences and the provider's key in the
/// Keychain; nil when no usable model is set up, so Apple Translation is used (architecture
/// 6.5). The key itself is never logged. In a Debug build, `DICT_MOCK_MODEL` in
/// `environment` replaces all of that with the local mock model (`mockModelBaseURL`).
func configuredModel(
  _ preferences: ModelPreferences, presets: [ProviderPreset], secrets: any SecretStore,
  environment: [String: String] = ProcessInfo.processInfo.environment
) -> (configuration: ModelConfiguration, apiKey: String?)? {
  if let baseURL = mockModelBaseURL(environment) {
    return mockModel(baseURL: baseURL, presets: presets)
  }
  guard let providerID = preferences.providerID else { return nil }
  var key: String?
  do {
    key = try secrets.secret(for: providerID)?.trimmingCharacters(in: .whitespacesAndNewlines)
  } catch {
    Log.store.error(
      "Keychain read failed for \(providerID, privacy: .public): \(error.status, privacy: .public)")
  }
  if key?.isEmpty == true { key = nil }
  do {
    let configuration = try preferences.configuration(presets: presets, hasKey: key != nil)
    return (configuration, key)
  } catch {
    Log.model.info(
      "model not usable (\(String(describing: error), privacy: .public)); using Apple Translation")
    return nil
  }
}

/// The base URL of the local mock model (`scripts/fake-model.py`, started by `make run-mock`)
/// from the `DICT_MOCK_MODEL` environment variable; nil when unset, and always nil in a
/// Release build. With it, the saved preferences and the Keychain go unused, so nothing
/// is sent to a real provider.
func mockModelBaseURL(
  _ environment: [String: String] = ProcessInfo.processInfo.environment
) -> String? {
  #if DEBUG
    let value = environment["DICT_MOCK_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    return value?.isEmpty == false ? value : nil
  #else
    return nil
  #endif
}

/// The custom provider at the mock's base URL with placeholder model and key. A URL that is
/// not usable (plain http off this Mac, say) means no model, never the real one.
private func mockModel(
  baseURL: String, presets: [ProviderPreset]
) -> (configuration: ModelConfiguration, apiKey: String?)? {
  let preferences = ModelPreferences(
    providerID: ProviderPreset.customID, model: "mock", baseURL: baseURL)
  do {
    return (try preferences.configuration(presets: presets, hasKey: true), "mock")
  } catch {
    Log.model.error(
      "DICT_MOCK_MODEL not usable (\(String(describing: error), privacy: .public)); no model")
    return nil
  }
}

/// The translation engine for the saved model preferences: the model when one is usable,
/// otherwise Apple Translation alone.
@MainActor
func makeTranslationEngine(
  _ preferences: ModelPreferences, presets: [ProviderPreset], secrets: any SecretStore
) -> TranslationEngine {
  let model = configuredModel(preferences, presets: presets, secrets: secrets).map {
    ModelTranslator(
      model: ChatCompletionsModel(
        endpoint: $0.configuration.endpoint, rules: $0.configuration.rules, apiKey: $0.apiKey))
  }
  return TranslationEngine(model: model)
}

/// The proofreader for the saved model preferences; nil without a usable model, since
/// proofreading has no fallback.
func makeProofreader(
  _ preferences: ModelPreferences, presets: [ProviderPreset], secrets: any SecretStore
) -> Proofreader? {
  configuredModel(preferences, presets: presets, secrets: secrets).map {
    Proofreader(
      model: ChatCompletionsModel(
        endpoint: $0.configuration.endpoint, rules: $0.configuration.rules, apiKey: $0.apiKey))
  }
}

/// The card maker for the saved model preferences; nil without a usable model, and then the
/// card shows the dictionary layer alone.
func makeCardMaker(
  _ preferences: ModelPreferences, presets: [ProviderPreset], secrets: any SecretStore
) -> CardMaker? {
  configuredModel(preferences, presets: presets, secrets: secrets).map {
    CardMaker(
      model: ChatCompletionsModel(
        endpoint: $0.configuration.endpoint, rules: $0.configuration.rules, apiKey: $0.apiKey))
  }
}
