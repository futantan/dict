// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Observation

/// The result of the "Test" button.
enum ConnectionStatus: Equatable {
  case idle
  /// The settings are incomplete or the key can't be read: no request was sent.
  case failed(ConnectionFailure)
  /// The checks, filled in as they finish.
  case checked(ConnectionReport)

  var isTesting: Bool {
    guard case .checked(let report) = self else { return false }
    return report.isRunning
  }
}

/// The state of one check of the "Test" button.
enum CheckState: Equatable {
  case waiting
  case running
  case passed
  case failed(ConnectionFailure)
  /// Not run because an earlier check failed.
  case skipped

  var isPending: Bool { self == .waiting || self == .running }
}

/// The three checks of the "Test" button (architecture 6.8): translate a sentence and time
/// the first content; decode a strict `json_schema` answer; notice thinking.
struct ConnectionReport: Equatable {
  var translation = CheckState.waiting
  /// The translation's time to its first answer text.
  var firstContent: Duration?
  var structuredOutput = CheckState.waiting
  /// Whether either request showed thinking.
  var sawThinking = false

  var isRunning: Bool { translation.isPending || structuredOutput.isPending }

  /// The third check: whether to warn that the model thinks, so looking up words will be
  /// slow. Nil until both requests are done, or when the translation failed.
  var isThinking: Bool? {
    guard translation == .passed, !structuredOutput.isPending else { return nil }
    return ModelCheck.isThinking(firstContent: firstContent, sawThinking: sawThinking)
  }

  /// The service doesn't know the model name: offer its model list (architecture 6.4).
  var suggestsModelList: Bool { translation == .failed(.model(.modelNotFound)) }
}

enum ConnectionFailure: Error, Equatable {
  case setup(ModelSetupIssue)
  case model(ModelError)
  case keychain(OSStatus)
  /// The answer to the strict JSON schema request was unusable.
  case structuredOutput(ProofreadError)
  /// The service has no model list at this address.
  case listUnsupported
  /// Any other error, already free of the key.
  case other(String)
}

/// The "List Available Models" result.
enum ModelListStatus: Equatable {
  case idle
  case loading
  /// Sorted names; empty when the service has none.
  case loaded([String])
  case failed(ConnectionFailure)
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
  private(set) var modelList = ModelListStatus.idle
  /// The last Keychain failure, shown under the key field.
  private(set) var keychainStatus: OSStatus?

  let presets: [ProviderPreset]

  typealias ModelFactory = @Sendable (ModelConfiguration, _ apiKey: String?) -> any TextModel
  typealias ModelLister =
    @Sendable (ModelEndpoint, ModelListStyle, _ apiKey: String?) async throws -> [String]

  @ObservationIgnored private let store: PreferencesStore
  @ObservationIgnored private let secrets: any SecretStore
  @ObservationIgnored private let makeModel: ModelFactory
  @ObservationIgnored private let lister: ModelLister
  @ObservationIgnored private var savedKey = ""
  @ObservationIgnored private var testTask: Task<Void, Never>?
  @ObservationIgnored private var listTask: Task<Void, Never>?

  init(
    defaults: UserDefaults = .standard, secrets: any SecretStore = CachedSecretStore.app,
    presets: [ProviderPreset] = (try? ProviderPreset.all()) ?? [],
    makeModel: @escaping ModelFactory = SettingsModel.chatCompletionsModel,
    listModels: @escaping ModelLister = { try await DictCore.listModels($0, style: $1, apiKey: $2) }
  ) {
    store = PreferencesStore(defaults: defaults)
    self.secrets = secrets
    self.presets = presets
    self.makeModel = makeModel
    self.lister = listModels
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

  /// Applies `change` and saves. A change to the model settings clears the test result; a
  /// change of service clears the model list, but choosing a model from it does not.
  func update(_ change: (inout Preferences) -> Void) {
    var next = preferences
    change(&next)
    guard next != preferences else { return }
    if next.model != preferences.model { resetConnection() }
    if next.model.providerID != preferences.model.providerID
      || next.model.baseURL != preferences.model.baseURL
    {
      resetModelList()
    }
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
      resetModelList()
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

  /// The saved key, or nil when there is none.
  private var apiKey: String? { savedKey.isEmpty ? nil : savedKey }

  // MARK: - Model list

  /// Whether "List Available Models" can run: everything but the model name is filled in.
  var canListModels: Bool {
    guard modelList != .loading else { return false }
    do {
      _ = try preferences.model.listEndpoint(presets: presets, hasKey: !trimmedDraft.isEmpty)
      return true
    } catch {
      return false
    }
  }

  /// Asks the service which models it offers: Ollama's tags, or `GET <base URL>/models`.
  func listModels() {
    commitKey()
    listTask?.cancel()
    guard let preset = selectedPreset else { return }
    let endpoint: ModelEndpoint
    do {
      endpoint = try preferences.model.listEndpoint(presets: presets, hasKey: apiKey != nil)
    } catch {
      modelList = .failed(.setup(error))
      return
    }
    if let keychainStatus {
      modelList = .failed(.keychain(keychainStatus))
      return
    }
    let key = apiKey
    let lister = lister
    modelList = .loading
    listTask = Task {
      let status: ModelListStatus
      do {
        status = .loaded(try await lister(endpoint, preset.modelList, key))
      } catch is CancellationError {
        return
      } catch {
        status = .failed(Self.failure(error, redacting: key))
      }
      guard !Task.isCancelled else { return }
      modelList = status
      Log.model.info(
        "Model list for \(endpoint.providerID, privacy: .public): \(status.logLabel, privacy: .public)"
      )
    }
  }

  /// Uses a model from the list.
  func chooseModel(_ name: String) {
    update { $0.model.model = name }
  }

  private func resetModelList() {
    listTask?.cancel()
    listTask = nil
    modelList = .idle
  }

  // MARK: - Connection test

  /// Runs the checks of architecture 6.8 one after another, showing each result as it
  /// comes: a translation, then a strict structured-output request; thinking is judged from
  /// both. A failed translation skips the rest.
  func testConnection() {
    commitKey()
    testTask?.cancel()
    let configuration: ModelConfiguration
    do {
      configuration = try preferences.model.configuration(presets: presets, hasKey: apiKey != nil)
    } catch {
      connection = .failed(.setup(error))
      return
    }
    if let keychainStatus {
      connection = .failed(.keychain(keychainStatus))
      return
    }
    let key = apiKey
    let model = makeModel(configuration, key)
    let target = translationTarget
    var started = ConnectionReport()
    started.translation = .running
    connection = .checked(started)
    testTask = Task { [started] in
      var report = started
      do {
        let result = try await ModelCheck.checkTranslation(model, into: target)
        report.translation = .passed
        report.firstContent = result.firstContent
        report.sawThinking = result.sawThinking
        report.structuredOutput = .running
      } catch is CancellationError {
        return
      } catch {
        report.translation = .failed(Self.failure(error, redacting: key))
        report.structuredOutput = .skipped
      }
      guard !Task.isCancelled else { return }
      connection = .checked(report)
      // An unknown model name: show the names the service does know (architecture 6.4).
      if report.suggestsModelList && canListModels { listModels() }

      if report.structuredOutput == .running {
        do {
          let thought = try await ModelCheck.checkStructuredOutput(model)
          report.structuredOutput = .passed
          report.sawThinking = report.sawThinking || thought
        } catch is CancellationError {
          return
        } catch {
          report.structuredOutput = .failed(Self.failure(error, redacting: key))
        }
        guard !Task.isCancelled else { return }
        connection = .checked(report)
      }
      Log.model.info(
        "Connection test for \(configuration.endpoint.providerID, privacy: .public): \(report.logLabel, privacy: .public)"
      )
    }
  }

  /// The test sentence goes into my language, or into the language I learn when mine is
  /// English, since the sample is English.
  private var translationTarget: Locale.Language {
    let mine = preferences.myLanguage
    return Locale.Language(identifier: mine == "en" ? preferences.learningLanguage : mine)
  }

  nonisolated static func failure(_ error: any Error, redacting key: String?)
    -> ConnectionFailure
  {
    switch error {
    case let error as ModelError: .model(redact(error, key: key))
    case let error as ProofreadError: .structuredOutput(error)
    case is ModelListError: .listUnsupported
    default: .other(redact(error.localizedDescription, key: key))
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

extension ConnectionReport {
  /// For the log: which checks passed, never any text.
  fileprivate var logLabel: String {
    func label(_ state: CheckState) -> String {
      switch state {
      case .passed: "passed"
      case .failed: "failed"
      case .skipped: "skipped"
      case .waiting, .running: "unfinished"
      }
    }
    return
      "translation \(label(translation)), structured output \(label(structuredOutput)), thinking \(isThinking.map(String.init) ?? "unknown")"
  }
}

extension ModelListStatus {
  fileprivate var logLabel: String {
    switch self {
    case .idle, .loading: "unfinished"
    case .loaded(let names): "\(names.count) models"
    case .failed: "failed"
    }
  }
}

#if DEBUG
  extension SettingsModel {
    /// Sets the test result directly, for renders of each state.
    func showConnection(_ status: ConnectionStatus) { connection = status }

    /// Sets the model list directly, for renders of each state.
    func showModelList(_ status: ModelListStatus) { modelList = status }
  }

  extension ConnectionReport {
    /// A report with the translation done, for renders.
    static func translated(
      after firstContent: Duration, structuredOutput: CheckState = .passed,
      sawThinking: Bool = false
    ) -> ConnectionReport {
      ConnectionReport(
        translation: .passed, firstContent: firstContent, structuredOutput: structuredOutput,
        sawThinking: sawThinking)
    }

    /// A report whose translation failed, for renders.
    static func failed(_ failure: ConnectionFailure) -> ConnectionReport {
      ConnectionReport(translation: .failed(failure), structuredOutput: .skipped)
    }
  }
#endif
