// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Testing

@testable import DictApp

/// A model that answers each request from a script, without any network.
private struct ScriptedModel: TextModel {
  let reply: @Sendable (ModelRequest) -> (events: [StreamEvent], error: (any Error)?)

  func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, Error> {
    let (events, error) = reply(request)
    return AsyncThrowingStream { continuation in
      events.forEach { continuation.yield($0) }
      continuation.finish(throwing: error)
    }
  }
}

/// Good answers to the two requests of the "Test" button.
private let translated: [StreamEvent] = [.text("你能在周五前把报告发给我吗？"), .finished(.complete, nil)]
private let proofread: [StreamEvent] = [
  .text(#"{"edits":[{"kind":"word_form","wrong":"She go","right":"She went"}]}"#),
  .finished(.complete, nil),
]

private func isStructured(_ request: ModelRequest) -> Bool {
  if case .jsonSchema = request.output { return true }
  return false
}

private final class Builds: @unchecked Sendable {
  var calls: [(ModelConfiguration, String?)] = []
  var requests: [ModelRequest] = []
  var lists: [(ModelEndpoint, ModelListStyle, String?)] = []
}

@MainActor
struct SettingsModelTests {
  private let defaults: UserDefaults
  private let secrets: any SecretStore = InMemorySecretStore()
  private let builds = Builds()

  init() {
    defaults = .scratch("SettingsModelTests")
  }

  private func makeModel(
    translation: [StreamEvent] = translated, structured: [StreamEvent] = proofread,
    error: (any Error)? = nil, structuredError: (any Error)? = nil,
    list: Result<[String], any Error> = .success(["b-model", "a-model"])
  ) -> SettingsModel {
    let builds = builds
    return SettingsModel(
      defaults: defaults, secrets: secrets,
      makeModel: { configuration, key in
        builds.calls.append((configuration, key))
        return ScriptedModel { request in
          builds.requests.append(request)
          return isStructured(request)
            ? (structured, structuredError) : (error == nil ? translation : [], error)
        }
      },
      listModels: { endpoint, style, key in
        builds.lists.append((endpoint, style, key))
        return try list.get()
      })
  }

  private func waitForResult(_ model: SettingsModel) async {
    for _ in 0..<200 where model.connection.isTesting {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  private func waitForList(_ model: SettingsModel) async {
    for _ in 0..<200 where model.modelList == .loading {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  private func checks(_ model: SettingsModel) -> ConnectionReport? {
    guard case .checked(let report) = model.connection else {
      Issue.record("Expected a report, got \(model.connection)")
      return nil
    }
    return report
  }

  private func testedOpenAI(_ model: SettingsModel) async {
    model.selectProvider("openai")
    model.keyDraft = "sk-x"
    model.testConnection()
    await waitForResult(model)
  }

  // MARK: - Preferences

  @Test func startsWithDefaultsAndPersistsChanges() {
    let model = makeModel()
    #expect(model.preferences == Preferences())

    model.update { $0.setLearningLanguage("ja") }

    #expect(PreferencesStore(defaults: defaults).load().learningLanguage == "ja")
    #expect(makeModel().preferences.learningLanguage == "ja")
  }

  @Test func turningOffKeepingTheFormattingIsSaved() {
    let model = makeModel()
    #expect(model.preferences.keepsFormatting)

    model.update { $0.keepsFormatting = false }

    #expect(PreferencesStore(defaults: defaults).load().keepsFormatting == false)
    #expect(makeModel().preferences.keepsFormatting == false)
  }

  @Test func storeReadsGarbageAsDefaults() {
    defaults.set(Data("not json".utf8), forKey: PreferencesStore.key)

    #expect(PreferencesStore(defaults: defaults).load() == Preferences())
  }

  @Test func selectingAProviderResetsItsFields() {
    let model = makeModel()
    model.selectProvider("custom")
    model.update {
      $0.model.model = "llama3"
      $0.model.baseURL = "https://api.example.org/v1"
    }

    model.selectProvider("ollama")

    #expect(model.preferences.model == ModelPreferences(providerID: "ollama"))
  }

  // MARK: - Key

  @Test func keyGoesToTheSecretStoreNotUserDefaults() throws {
    let model = makeModel()
    model.selectProvider("openai")
    model.keyDraft = "  sk-test-123 \n"

    model.commitKey()

    #expect(try secrets.secret(for: "openai") == "sk-test-123")
    let stored = defaults.dictionaryRepresentation().values.map { "\($0)" }.joined()
    #expect(!stored.contains("sk-test-123"))
    let blob = try #require(defaults.data(forKey: PreferencesStore.key))
    #expect(!String(decoding: blob, as: UTF8.self).contains("sk-test"))
  }

  @Test func eachProviderKeepsItsOwnKey() throws {
    try secrets.setSecret("sk-openai", for: "openai")
    let model = makeModel()
    model.selectProvider("openai")
    #expect(model.keyDraft == "sk-openai")

    model.selectProvider("custom")
    #expect(model.keyDraft == "")
    model.keyDraft = "sk-custom"

    model.selectProvider("openai")  // Switching saves the custom key.
    #expect(model.keyDraft == "sk-openai")
    #expect(try secrets.secret(for: "custom") == "sk-custom")
  }

  @Test func clearingTheFieldRemovesTheKey() throws {
    try secrets.setSecret("sk-openai", for: "openai")
    let model = makeModel()
    model.selectProvider("openai")

    model.keyDraft = ""
    model.commitKey()

    #expect(try secrets.secret(for: "openai") == nil)
  }

  @Test func ollamaTakesNoKey() throws {
    let model = makeModel()
    model.selectProvider("ollama")
    model.keyDraft = "ignored"

    model.commitKey()

    #expect(!model.acceptsKey)
    #expect(try secrets.secret(for: "ollama") == nil)
  }

  @Test func setupIssueFollowsTheFields() {
    let model = makeModel()
    #expect(model.setupIssue == .noProvider)

    model.selectProvider("openai")
    #expect(model.setupIssue == .missingKey)

    model.keyDraft = "sk-x"
    #expect(model.setupIssue == nil)

    model.update { $0.model.baseURL = "http://api.example.com/v1" }
    #expect(model.setupIssue == .insecureBaseURL)
  }

  // MARK: - Connection test

  @Test func successfulTestBuildsTheEndpointWithTheSavedKey() async throws {
    let model = makeModel()
    model.selectProvider("openai")
    model.keyDraft = "sk-live"

    model.testConnection()
    #expect(model.connection.isTesting)
    await waitForResult(model)

    let (configuration, key) = try #require(builds.calls.last)
    #expect(configuration.endpoint.providerID == "openai")
    #expect(configuration.endpoint.auth == .bearer)
    #expect(key == "sk-live")
    #expect(try secrets.secret(for: "openai") == "sk-live")
  }

  /// Architecture 6.8: translate a sentence, then a strict schema request, then judge
  /// thinking from both.
  @Test func threeChecksRunInOrderAndPass() async throws {
    let model = makeModel()
    await testedOpenAI(model)

    let report = try #require(checks(model))
    #expect(report.translation == .passed)
    #expect(report.firstContent != nil)
    #expect(report.structuredOutput == .passed)
    #expect(report.isThinking == false)
    #expect(!model.connection.isTesting)
    #expect(builds.requests.map(isStructured) == [false, true])
    #expect(builds.requests.last?.output == ModelCheck.structuredOutputRequest(nonce: "x").output)
  }

  @Test func translationGoesIntoMyLanguage() async throws {
    let model = makeModel()
    model.update { $0.setMyLanguage("ja") }
    await testedOpenAI(model)

    let request = try #require(builds.requests.first)
    #expect(request.system.contains("Japanese"))
  }

  @Test func translationFailureSkipsTheOtherChecks() async throws {
    let model = makeModel(error: ModelError.modelNotFound)
    await testedOpenAI(model)

    let report = try #require(checks(model))
    #expect(report.translation == .failed(.model(.modelNotFound)))
    #expect(report.structuredOutput == .skipped)
    #expect(report.isThinking == nil)
    #expect(builds.requests.count == 1)
    #expect(report.suggestsModelList)
  }

  /// Architecture 6.4: an unknown model name brings up the names the service knows.
  @Test func unknownModelListsTheAvailableOnes() async throws {
    let model = makeModel(error: ModelError.modelNotFound)
    await testedOpenAI(model)
    await waitForList(model)

    #expect(model.modelList == .loaded(["b-model", "a-model"]))
    #expect(builds.lists.count == 1)
  }

  @Test func otherFailuresDoNotList() async {
    let model = makeModel(error: ModelError.unauthorized)
    await testedOpenAI(model)

    #expect(model.modelList == .idle)
    #expect(builds.lists.isEmpty)
  }

  @Test func structuredOutputFailureKeepsTheTranslationResult() async throws {
    let model = makeModel(
      structured: [.text("Sure! She went to school."), .finished(.complete, nil)])
    await testedOpenAI(model)

    let report = try #require(checks(model))
    #expect(report.translation == .passed)
    #expect(report.structuredOutput == .failed(.structuredOutput(.malformed)))
    #expect(!report.suggestsModelList)
  }

  @Test func structuredModelErrorIsReported() async throws {
    let model = makeModel(structuredError: ModelError.badRequest(message: "schema not supported"))
    await testedOpenAI(model)

    #expect(
      checks(model)?.structuredOutput
        == .failed(.model(.badRequest(message: "schema not supported"))))
  }

  @Test func thinkingDeltasRaiseTheHint() async throws {
    let model = makeModel(translation: [.thinking] + translated)
    await testedOpenAI(model)

    let report = try #require(checks(model))
    #expect(report.translation == .passed)
    #expect(report.sawThinking)
    #expect(report.isThinking == true)
  }

  @Test func thinkingInTheStructuredRequestAlsoCounts() async throws {
    let model = makeModel(structured: [.thinking] + proofread)
    await testedOpenAI(model)

    #expect(checks(model)?.isThinking == true)
  }

  @Test func slowFirstContentRaisesTheHint() {
    var report = ConnectionReport()
    report.translation = .passed
    report.structuredOutput = .passed
    report.firstContent = .milliseconds(3500)
    #expect(report.isThinking == true)

    report.firstContent = .milliseconds(900)
    #expect(report.isThinking == false)

    report.structuredOutput = .running
    #expect(report.isThinking == nil)
  }

  @Test func customWithoutKeyIsTestedWithoutAuth() async throws {
    let model = makeModel()
    model.selectProvider("custom")
    model.update {
      $0.model.model = "llama3"
      $0.model.baseURL = "http://localhost:8080/v1"
    }

    model.testConnection()
    await waitForResult(model)

    let (configuration, key) = try #require(builds.calls.last)
    #expect(configuration.endpoint.auth == .none)
    #expect(key == nil)
  }

  @Test func customOptionsReachTheEndpoint() async throws {
    let model = makeModel()
    model.selectProvider("custom")
    model.update {
      $0.model.model = "deepseek-chat"
      $0.model.baseURL = "https://api.deepseek.com/v1"
      $0.model.thinking = .providerDefault
      $0.model.tokenLimitField = "max_completion_tokens"
      $0.model.jsonMode = .object
    }

    model.testConnection()
    await waitForResult(model)

    let endpoint = try #require(builds.calls.last?.0.endpoint)
    #expect(endpoint.thinking == .providerDefault)
    #expect(endpoint.tokenLimitField == "max_completion_tokens")
    #expect(endpoint.jsonMode == .object)
    #expect(PreferencesStore(defaults: defaults).load().model.jsonMode == .object)
  }

  @Test func setupProblemFailsWithoutCallingTheModel() {
    let model = makeModel()
    model.selectProvider("openai")

    model.testConnection()

    #expect(model.connection == .failed(.setup(.missingKey)))
    #expect(builds.calls.isEmpty)
  }

  @Test(arguments: [
    ModelError.unauthorized, .modelNotFound, .rateLimited(retryAfter: nil), .server(status: 503),
    .network(code: -1009), .timedOut(.firstEvent), .malformedResponse,
  ])
  func modelErrorsAreReported(error: ModelError) async {
    let model = makeModel(error: error)
    await testedOpenAI(model)

    #expect(checks(model)?.translation == .failed(.model(error)))
  }

  @Test func errorMessagesNeverShowTheKey() async {
    let model = makeModel(
      error: ModelError.badRequest(message: "Incorrect API key provided: sk-secret-9"))
    model.selectProvider("openai")
    model.keyDraft = "sk-secret-9"

    model.testConnection()
    await waitForResult(model)

    #expect(
      checks(model)?.translation
        == .failed(.model(.badRequest(message: "Incorrect API key provided: ••••"))))
  }

  @Test func streamWithoutTextIsAnEmptyResponse() async {
    let model = makeModel(translation: [.finished(.complete, nil)])
    await testedOpenAI(model)

    #expect(checks(model)?.translation == .failed(.model(.emptyResponse)))
  }

  @Test func editingTheModelClearsTheResult() async {
    let model = makeModel()
    await testedOpenAI(model)

    model.update { $0.model.model = "gpt-5-nano" }

    #expect(model.connection == .idle)
  }

  // MARK: - Model list

  /// Ollama's first run: no model name yet, which is why the user lists them.
  @Test func listsModelsWithoutAModelName() async throws {
    let model = makeModel()
    model.selectProvider("ollama")
    #expect(model.setupIssue == .missingModel)
    #expect(model.canListModels)

    model.listModels()
    #expect(model.modelList == .loading)
    await waitForList(model)

    #expect(model.modelList == .loaded(["b-model", "a-model"]))
    let (endpoint, style, key) = try #require(builds.lists.last)
    #expect(style == .ollama)
    #expect(endpoint.baseURL == URL(string: "http://localhost:11434/v1"))
    #expect(endpoint.auth == .none)
    #expect(key == nil)
  }

  @Test func customListsWithItsKey() async throws {
    let model = makeModel()
    model.selectProvider("custom")
    model.update { $0.model.baseURL = "https://api.deepseek.com/v1" }
    model.keyDraft = "sk-custom"

    model.listModels()
    await waitForList(model)

    let (endpoint, style, key) = try #require(builds.lists.last)
    #expect(style == .openAI)
    #expect(endpoint.auth == .bearer)
    #expect(key == "sk-custom")
  }

  @Test func listingNeedsTheKeyAndBaseURL() {
    let model = makeModel()
    model.selectProvider("openai")
    #expect(!model.canListModels)

    model.listModels()

    #expect(model.modelList == .failed(.setup(.missingKey)))
    #expect(builds.lists.isEmpty)

    model.selectProvider("custom")
    #expect(!model.canListModels)
  }

  @Test(arguments: [
    (ModelError.unauthorized as any Error, ConnectionFailure.model(.unauthorized)),
    (ModelError.network(code: -1004), .model(.network(code: -1004))),
    (ModelListError.unsupported, .listUnsupported),
  ])
  func listFailuresAreReported(error: any Error, expected: ConnectionFailure) async {
    let model = makeModel(list: .failure(error))
    model.selectProvider("ollama")

    model.listModels()
    await waitForList(model)

    #expect(model.modelList == .failed(expected))
  }

  @Test func choosingAListedModelKeepsTheList() async {
    let model = makeModel()
    model.selectProvider("ollama")
    model.listModels()
    await waitForList(model)

    model.chooseModel("a-model")

    #expect(model.preferences.model.model == "a-model")
    #expect(model.modelList == .loaded(["b-model", "a-model"]))
    #expect(model.setupIssue == nil)
  }

  @Test func changingTheServiceClearsTheList() async {
    let model = makeModel()
    model.selectProvider("custom")
    model.update { $0.model.baseURL = "https://api.deepseek.com/v1" }
    model.listModels()
    await waitForList(model)

    model.update { $0.model.baseURL = "https://openrouter.ai/api/v1" }
    #expect(model.modelList == .idle)

    model.listModels()
    await waitForList(model)
    model.keyDraft = "sk-new"
    model.commitKey()
    #expect(model.modelList == .idle)

    model.listModels()
    await waitForList(model)
    model.selectProvider("ollama")
    #expect(model.modelList == .idle)
  }

  // MARK: - Messages

  @Test func everyFailureHasAMessage() {
    let failures: [ConnectionFailure] =
      [
        .setup(.unknownProvider), .setup(.missingBaseURL), .setup(.invalidBaseURL),
        .setup(.insecureBaseURL), .setup(.missingModel), .setup(.missingKey),
        .model(.missingKey), .model(.unauthorized), .model(.modelNotFound),
        .model(.rateLimited(retryAfter: .seconds(3))), .model(.badRequest(message: "bad")),
        .model(.server(status: 500)), .model(.network(code: -1009)),
        .model(.network(code: -1004)), .model(.timedOut(.idle)), .model(.emptyResponse),
        .model(.malformedResponse), .keychain(-25308), .other("boom"),
        .structuredOutput(.malformed), .structuredOutput(.truncated),
        .structuredOutput(.refused), .structuredOutput(.interrupted), .listUnsupported,
      ]
    for failure in failures {
      #expect(!failure.message.isEmpty, "\(failure)")
    }
  }
}
