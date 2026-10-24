// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
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

/// The ChatGPT account row (docs/reviews/chatgpt-login.md 4.9).
enum ChatGPTStatus: Equatable {
  /// No account; `previousEmail` is the last one signed in on this Mac, whose sign-in ended
  /// or was signed out.
  case signedOut(previousEmail: String?)
  /// Waiting for the browser.
  case signingIn
  /// `canUsePlan` is false when the user left plan usage unticked on the consent page.
  case signedIn(email: String?, canUsePlan: Bool)

  var isSignedIn: Bool {
    guard case .signedIn = self else { return false }
    return true
  }
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
  private(set) var chatGPT = ChatGPTStatus.signedOut(previousEmail: nil)
  /// Why the last ChatGPT sign-in failed, or that signing out was not confirmed.
  private(set) var chatGPTNote: String?
  /// The guidelines' one-time notice after the first sign-in with plan usage.
  private(set) var showsPlanWelcome = false

  let presets: [ProviderPreset]

  typealias ModelFactory = @Sendable (ModelConfiguration, _ apiKey: String?) -> any TextModel
  typealias ModelLister =
    @Sendable (ModelEndpoint, ModelListStyle, _ apiKey: String?) async throws -> [String]
  typealias ChatGPTSignInRunner = @Sendable (ChatGPTAccount) async throws -> ChatGPTCredential
  typealias ChatGPTLister = @Sendable (ChatGPTAccount) async throws -> [String]

  @ObservationIgnored private let store: PreferencesStore
  @ObservationIgnored private let secrets: any SecretStore
  @ObservationIgnored private let makeModel: ModelFactory
  @ObservationIgnored private let lister: ModelLister
  @ObservationIgnored private var savedKey = ""
  @ObservationIgnored private var testTask: Task<Void, Never>?
  @ObservationIgnored private var listTask: Task<Void, Never>?
  @ObservationIgnored private var signInTask: Task<Void, Never>?
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored let chatGPTAccount: ChatGPTAccount
  @ObservationIgnored private let signIn: ChatGPTSignInRunner
  @ObservationIgnored private let chatGPTLister: ChatGPTLister
  /// A render set the account row; reading the Keychain must not replace it.
  @ObservationIgnored private var pinsChatGPT = false

  /// - Parameter chatGPT: the ChatGPT sign-in; by default the app's when `secrets` is the
  ///   app's Keychain, else one kept in `secrets` (at the app's endpoints, so the mock's
  ///   under `DICT_MOCK_MODEL`), so tests and demos never see a real sign-in.
  init(
    defaults: UserDefaults = .standard, secrets: any SecretStore = CachedSecretStore.app,
    presets: [ProviderPreset] = (try? ProviderPreset.all()) ?? [],
    makeModel: ModelFactory? = nil,
    listModels: @escaping ModelLister = {
      try await DictCore.listModels($0, style: $1, apiKey: $2)
    },
    chatGPT: ChatGPTAccount? = nil,
    signIn: @escaping ChatGPTSignInRunner = SettingsModel.signInInBrowser,
    listChatGPTModels: @escaping ChatGPTLister = {
      try await DictCore.listChatGPTModels(endpoints: $0.endpoints, tokens: $0.session)
    }
  ) {
    store = PreferencesStore(defaults: defaults)
    self.defaults = defaults
    self.secrets = secrets
    self.presets = presets
    let account =
      chatGPT
      ?? ((secrets as? CachedSecretStore) === CachedSecretStore.app
        ? .app : ChatGPTAccount(endpoints: ChatGPTAccount.app.endpoints, secrets: secrets))
    chatGPTAccount = account
    self.makeModel = makeModel ?? { makeTextModel($0, apiKey: $1, chatGPT: account) }
    self.lister = listModels
    self.signIn = signIn
    chatGPTLister = listChatGPTModels
    preferences = store.load()
    loadKey()
    refreshChatGPT()
  }

  nonisolated static func chatCompletionsModel(
    _ configuration: ModelConfiguration, apiKey: String?
  ) -> any TextModel {
    ChatCompletionsModel(
      endpoint: configuration.endpoint, rules: configuration.rules, apiKey: apiKey)
  }

  /// Signs in in the default browser, then brings Dict back to the front.
  nonisolated static func signInInBrowser(_ account: ChatGPTAccount) async throws
    -> ChatGPTCredential
  {
    let signIn = ChatGPTSignIn(
      account: account, openURL: { url in _ = await MainActor.run { NSWorkspace.shared.open(url) } }
    )
    let credential = try await signIn.run()
    await MainActor.run { NSApp.activate() }
    return credential
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
    cancelChatGPTSignIn()
    update { $0.model = ModelPreferences(providerID: id) }
    loadKey()
    refreshChatGPT()
  }

  /// Whether the selected provider is the ChatGPT plan, signed in instead of a key.
  var isChatGPT: Bool { selectedPreset?.wire == .chatGPT }

  /// Whether the selected provider takes a key: OpenAI needs one, a custom service may.
  var acceptsKey: Bool {
    guard let preset = selectedPreset else { return false }
    return preset.auth != .none
  }

  /// The first problem with the current fields, judged with the key as typed.
  var setupIssue: ModelSetupIssue? {
    do {
      _ = try preferences.model.configuration(presets: presets, hasKey: hasTypedCredential)
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

  /// A key is typed, or for ChatGPT an account is signed in.
  private var hasTypedCredential: Bool { isChatGPT ? chatGPT.isSignedIn : !trimmedDraft.isEmpty }

  /// A key is saved, or for ChatGPT an account is signed in.
  private var hasSavedCredential: Bool { isChatGPT ? chatGPT.isSignedIn : apiKey != nil }

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
      _ = try preferences.model.listEndpoint(presets: presets, hasKey: hasTypedCredential)
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
      endpoint = try preferences.model.listEndpoint(presets: presets, hasKey: hasSavedCredential)
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
    let chatGPTLister = chatGPTLister
    let account = chatGPTAccount
    modelList = .loading
    listTask = Task {
      let status: ModelListStatus
      do {
        status = .loaded(
          preset.wire == .chatGPT
            ? try await chatGPTLister(account)
            : try await lister(endpoint, preset.modelList, key))
      } catch is CancellationError {
        return
      } catch {
        status = .failed(Self.failure(error, redacting: key))
      }
      guard !Task.isCancelled else { return }
      modelList = status
      if preset.wire == .chatGPT, case .loaded(let names) = status { chooseChatGPTModel(names) }
      Log.model.info(
        "Model list for \(endpoint.providerID, privacy: .public): \(status.logLabel, privacy: .public)"
      )
    }
  }

  /// Uses a model from the list.
  func chooseModel(_ name: String) {
    update { $0.model.model = name }
  }

  /// Keeps the chosen ChatGPT model while the account lists it; otherwise OpenAI's default
  /// model when listed, else the first. The plan has no fixed default.
  private func chooseChatGPTModel(_ names: [String]) {
    guard !names.contains(preferences.model.model) else { return }
    let openAIDefault = presets.first { $0.id == "openai" }?.defaultModel
    if let name = names.first(where: { $0 == openAIDefault }) ?? names.first {
      chooseModel(name)
    }
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
      configuration = try preferences.model.configuration(
        presets: presets, hasKey: hasSavedCredential)
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

  // MARK: - ChatGPT

  /// Reads the sign-in from the Keychain, unless one is in progress. A sign-in that ended
  /// while the app was used (a refused refresh) shows as signed out here.
  func refreshChatGPT() {
    guard chatGPT != .signingIn, !pinsChatGPT else { return }
    if let credential = chatGPTAccount.savedCredential {
      chatGPT = .signedIn(email: credential.email, canUsePlan: credential.canUsePlan)
    } else {
      chatGPT = .signedOut(previousEmail: chatGPTAccount.lastEmail)
    }
    // Signed in from an earlier run: the model menu needs the account's list.
    if isChatGPT, case .signedIn(_, canUsePlan: true) = chatGPT, modelList == .idle {
      listModels()
    }
  }

  /// "Continue with ChatGPT": signs in in the browser, then lists the account's models.
  func signInWithChatGPT() {
    signInTask?.cancel()
    chatGPT = .signingIn
    chatGPTNote = nil
    let account = chatGPTAccount
    let signIn = signIn
    signInTask = Task {
      do {
        let credential = try await signIn(account)
        guard !Task.isCancelled else { return }
        chatGPT = .signedIn(email: credential.email, canUsePlan: credential.canUsePlan)
        resetConnection()
        if credential.canUsePlan {
          if !defaults.bool(forKey: Self.planWelcomeKey) { showsPlanWelcome = true }
          if isChatGPT { listModels() }
        }
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        chatGPT = .signedOut(previousEmail: nil)
        refreshChatGPT()
        chatGPTNote = ChatGPTText.signInFailure(error)
        Log.ui.error("ChatGPT sign-in failed: \(ChatGPTText.logLabel(error), privacy: .public)")
      }
    }
  }

  /// Stops waiting for the browser.
  func cancelChatGPTSignIn() {
    guard let signInTask else { return }
    signInTask.cancel()
    self.signInTask = nil
    if chatGPT == .signingIn { chatGPT = .signedOut(previousEmail: nil) }
    refreshChatGPT()
  }

  /// Revokes the sign-in and forgets it. When OpenAI does not confirm, says where to
  /// disconnect the app by hand.
  func signOutOfChatGPT() {
    cancelChatGPTSignIn()
    let session = chatGPTAccount.session
    chatGPTNote = nil
    Task {
      let confirmed = await session.signOut()
      chatGPTNote = confirmed ? nil : ChatGPTText.signOutUnconfirmed
      refreshChatGPT()
      resetConnection()
      resetModelList()
      Log.ui.info("ChatGPT signed out, revocation confirmed \(confirmed, privacy: .public)")
    }
  }

  /// "Got it" on the one-time notice.
  func dismissPlanWelcome() {
    showsPlanWelcome = false
    defaults.set(true, forKey: Self.planWelcomeKey)
  }

  private static let planWelcomeKey = "chatGPTPlanWelcomeShown"
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

    /// Sets the ChatGPT account row directly, for renders of each state.
    func showChatGPT(_ status: ChatGPTStatus, note: String? = nil) {
      pinsChatGPT = true
      chatGPT = status
      chatGPTNote = note
    }
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
