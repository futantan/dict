// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// The model to translate with, from the saved preferences and the provider's key in the
/// Keychain, or the ChatGPT sign-in; nil when no usable model is set up, so Apple
/// Translation is used (architecture 6.5). The key itself is never logged. In a Debug
/// build, `DICT_MOCK_MODEL` in `environment` replaces all of that with the local mock model
/// (`mockModelBaseURL`); the ChatGPT provider then signs in to the mock (`ChatGPTAccount`).
func configuredModel(
  _ preferences: ModelPreferences, presets: [ProviderPreset], secrets: any SecretStore,
  chatGPT: ChatGPTAccount = .app,
  environment: [String: String] = ProcessInfo.processInfo.environment
) -> (configuration: ModelConfiguration, apiKey: String?)? {
  let isChatGPT = preferences.providerID == ProviderPreset.chatGPTID
  if let baseURL = mockModelBaseURL(environment), !isChatGPT {
    return mockModel(baseURL: baseURL, presets: presets)
  }
  guard let providerID = preferences.providerID else { return nil }
  if isChatGPT {
    do {
      let configuration = try preferences.configuration(
        presets: presets, hasKey: chatGPT.savedCredential != nil)
      return (configuration, nil)
    } catch {
      Log.model.info(
        "ChatGPT not usable (\(String(describing: error), privacy: .public)); using Apple Translation"
      )
      return nil
    }
  }
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

/// The client for `configuration`: Chat Completions with the key, or the ChatGPT plan with
/// the shared sign-in.
func makeTextModel(
  _ configuration: ModelConfiguration, apiKey: String?, chatGPT: ChatGPTAccount = .app
) -> any TextModel {
  switch configuration.wire {
  case .chatCompletions:
    return ChatCompletionsModel(
      endpoint: configuration.endpoint, rules: configuration.rules, apiKey: apiKey)
  case .chatGPT:
    return ResponsesModel(
      model: configuration.endpoint.model, thinking: configuration.endpoint.thinking,
      rules: configuration.rules, endpoints: chatGPT.endpoints, tokens: chatGPT.session)
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
      model: makeTextModel($0.configuration, apiKey: $0.apiKey))
  }
  return TranslationEngine(model: model)
}

/// The translate-out engine for the saved model preferences: the model when one is usable,
/// otherwise Apple Translation alone.
@MainActor
func makeTranslateOutEngine(
  _ preferences: ModelPreferences, presets: [ProviderPreset], secrets: any SecretStore
) -> TranslateOutEngine {
  let model = configuredModel(preferences, presets: presets, secrets: secrets).map {
    ModelTranslator(
      model: makeTextModel($0.configuration, apiKey: $0.apiKey))
  }
  return TranslateOutEngine(model: model)
}

/// The proofreader for the saved model preferences; nil without a usable model, since
/// proofreading has no fallback.
func makeProofreader(
  _ preferences: ModelPreferences, presets: [ProviderPreset], secrets: any SecretStore
) -> Proofreader? {
  configuredModel(preferences, presets: presets, secrets: secrets).map {
    Proofreader(
      model: makeTextModel($0.configuration, apiKey: $0.apiKey))
  }
}

/// The card maker for the saved model preferences; nil without a usable model, and then the
/// card shows the dictionary layer alone.
func makeCardMaker(
  _ preferences: ModelPreferences, presets: [ProviderPreset], secrets: any SecretStore
) -> CardMaker? {
  configuredModel(preferences, presets: presets, secrets: secrets).map {
    CardMaker(
      model: makeTextModel($0.configuration, apiKey: $0.apiKey))
  }
}
