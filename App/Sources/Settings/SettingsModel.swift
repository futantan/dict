// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Observation

/// The result of the "Test" button.
enum ConnectionStatus: Equatable {
  case idle
  case testing
  /// The model answered; the time to its first event.
  case succeeded(Duration)
  case failed(ConnectionFailure)
}

enum ConnectionFailure: Error, Equatable {
  case setup(ModelSetupIssue)
  case model(ModelError)
  case keychain(OSStatus)
  /// Any other error, already free of the key.
  case other(String)
}

/// State behind the Settings window: preferences saved on every change, the API key of the
/// selected provider saved to the Keychain when the key field is committed.
@MainActor
@Observable
final class SettingsModel {
  private(set) var preferences: Preferences
  /// The key as shown in the field for the selected provider; not yet saved while edited.
  var keyDraft = ""
  private(set) var connection = ConnectionStatus.idle
  /// The last Keychain failure, shown under the key field.
  private(set) var keychainStatus: OSStatus?

  let presets: [ProviderPreset]

  typealias ModelFactory = @Sendable (ModelConfiguration, _ apiKey: String?) -> any TextModel

  @ObservationIgnored private let store: PreferencesStore
  @ObservationIgnored private let secrets: any SecretStore
  @ObservationIgnored private let makeModel: ModelFactory
  @ObservationIgnored private var savedKey = ""
  @ObservationIgnored private var testTask: Task<Void, Never>?

  init(
    defaults: UserDefaults = .standard, secrets: any SecretStore = CachedSecretStore.app,
    presets: [ProviderPreset] = (try? ProviderPreset.all()) ?? [],
    makeModel: @escaping ModelFactory = SettingsModel.chatCompletionsModel
  ) {
    store = PreferencesStore(defaults: defaults)
    self.secrets = secrets
    self.presets = presets
    self.makeModel = makeModel
    preferences = store.load()
    loadKey()
  }

  nonisolated static func chatCompletionsModel(
    _ configuration: ModelConfiguration, apiKey: String?
  ) -> any TextModel {
    ChatCompletionsModel(
      endpoint: configuration.endpoint, rules: configuration.rules, apiKey: apiKey)
  }

  // MARK: - Preferences

  /// Applies `change` and saves. A change to the model settings clears the test result.
  func update(_ change: (inout Preferences) -> Void) {
    var next = preferences
    change(&next)
    guard next != preferences else { return }
    if next.model != preferences.model { resetConnection() }
    preferences = next
    store.save(next)
  }

  var selectedPreset: ProviderPreset? {
    presets.first { $0.id == preferences.model.providerID }
  }

  /// Switches provider, saving the key typed for the previous one. Model and base URL go
  /// back to the new provider's defaults; its key is read from the Keychain.
  func selectProvider(_ id: String?) {
    guard id != preferences.model.providerID else { return }
    commitKey()
    update { $0.model = ModelPreferences(providerID: id) }
    loadKey()
  }

  /// Whether the selected provider takes a key: OpenAI needs one, a custom service may.
  var acceptsKey: Bool {
    guard let preset = selectedPreset else { return false }
    return preset.auth != .none
  }

  /// The first problem with the current fields, judged with the key as typed.
  var setupIssue: ModelSetupIssue? {
    do {
      _ = try preferences.model.configuration(presets: presets, hasKey: !trimmedDraft.isEmpty)
      return nil
    } catch {
      return error
    }
  }

  // MARK: - Key

  /// Saves the key field to the Keychain if it changed. An empty field removes the key.
  func commitKey() {
    guard let account = selectedPreset?.id, acceptsKey else { return }
    let key = trimmedDraft
    guard key != savedKey else { return }
    do {
      try secrets.setSecret(key, for: account)
      savedKey = key
      keychainStatus = nil
      resetConnection()
      Log.ui.info(
        "API key \(key.isEmpty ? "removed" : "saved", privacy: .public) for \(account, privacy: .public)"
      )
    } catch {
      keychainStatus = error.status
      Log.ui.error(
        "Keychain write failed for \(account, privacy: .public): \(error.status, privacy: .public)")
    }
  }

  private var trimmedDraft: String { keyDraft.trimmingCharacters(in: .whitespacesAndNewlines) }

  private func loadKey() {
    savedKey = ""
    keyDraft = ""
    keychainStatus = nil
    guard let account = selectedPreset?.id, acceptsKey else { return }
    do {
      savedKey = try secrets.secret(for: account) ?? ""
      keyDraft = savedKey
    } catch {
      keychainStatus = error.status
      Log.ui.error(
        "Keychain read failed for \(account, privacy: .public): \(error.status, privacy: .public)")
    }
  }

  // MARK: - Connection test

  /// Sends one minimal request and reports whether the model answered.
  func testConnection() {
    commitKey()
    testTask?.cancel()
    let configuration: ModelConfiguration
    do {
      configuration = try preferences.model.configuration(
        presets: presets, hasKey: !savedKey.isEmpty)
    } catch {
      connection = .failed(.setup(error))
      return
    }
    if let keychainStatus {
      connection = .failed(.keychain(keychainStatus))
      return
    }
    let key = savedKey.isEmpty ? nil : savedKey
    let model = makeModel(configuration, key)
    connection = .testing
    testTask = Task {
      let status = await Self.probe(model, redacting: key)
      guard !Task.isCancelled else { return }
      connection = status
      switch status {
      case .succeeded:
        Log.model.info(
          "Connection test succeeded for \(configuration.endpoint.providerID, privacy: .public)")
      default:
        Log.model.info(
          "Connection test failed for \(configuration.endpoint.providerID, privacy: .public)")
      }
    }
  }

  /// The request the "Test" button sends: as small as a real call can be.
  nonisolated static let probeRequest = ModelRequest(
    system: "Reply with the single word OK.", user: "OK", output: .text, maxOutputTokens: 16)

  /// Streams the probe request and stops at the first event from the model.
  nonisolated static func probe(_ model: any TextModel, redacting key: String?) async
    -> ConnectionStatus
  {
    let clock = ContinuousClock()
    let start = clock.now
    do {
      for try await event in model.stream(probeRequest) {
        switch event {
        case .text, .thinking, .finished: return .succeeded(clock.now - start)
        case .discardText: continue
        }
      }
      return .failed(.model(.emptyResponse))
    } catch let error as ModelError {
      return .failed(.model(redact(error, key: key)))
    } catch {
      return .failed(.other(redact(error.localizedDescription, key: key)))
    }
  }

  private nonisolated static func redact(_ error: ModelError, key: String?) -> ModelError {
    guard case .badRequest(let message) = error else { return error }
    return .badRequest(message: redact(message, key: key))
  }

  private nonisolated static func redact(_ text: String, key: String?) -> String {
    guard let key, !key.isEmpty else { return text }
    return text.replacingOccurrences(of: key, with: "••••")
  }

  private func resetConnection() {
    testTask?.cancel()
    testTask = nil
    connection = .idle
  }
}

#if DEBUG
  extension SettingsModel {
    /// Sets the test result directly, for renders of each state.
    func showConnection(_ status: ConnectionStatus) { connection = status }
  }
#endif
