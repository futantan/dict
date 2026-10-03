// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Testing

@testable import DictApp

/// A model that replays fixed events or fails, and records what it was built with.
private struct ScriptedModel: TextModel {
  let events: [StreamEvent]
  let error: (any Error)?

  func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, Error> {
    AsyncThrowingStream { continuation in
      events.forEach { continuation.yield($0) }
      continuation.finish(throwing: error)
    }
  }
}

private final class Builds: @unchecked Sendable {
  var calls: [(ModelConfiguration, String?)] = []
}

@MainActor
struct SettingsModelTests {
  private let defaults: UserDefaults
  private let secrets: any SecretStore = InMemorySecretStore()
  private let builds = Builds()

  init() throws {
    let suite = "SettingsModelTests.\(UUID().uuidString)"
    defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
  }

  private func makeModel(
    events: [StreamEvent] = [.text("OK"), .finished(.complete, nil)], error: (any Error)? = nil
  ) -> SettingsModel {
    let builds = builds
    return SettingsModel(defaults: defaults, secrets: secrets) { configuration, key in
      builds.calls.append((configuration, key))
      return ScriptedModel(events: events, error: error)
    }
  }

  private func waitForResult(_ model: SettingsModel) async {
    for _ in 0..<200 where model.connection == .testing {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  // MARK: - Preferences

  @Test func startsWithDefaultsAndPersistsChanges() {
    let model = makeModel()
    #expect(model.preferences == Preferences())

    model.update { $0.setLearningLanguage("ja") }

    #expect(PreferencesStore(defaults: defaults).load().learningLanguage == "ja")
    #expect(makeModel().preferences.learningLanguage == "ja")
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
    #expect(model.connection == .testing)
    await waitForResult(model)

    guard case .succeeded = model.connection else {
      Issue.record("Expected success, got \(model.connection)")
      return
    }
    let (configuration, key) = try #require(builds.calls.last)
    #expect(configuration.endpoint.providerID == "openai")
    #expect(configuration.endpoint.auth == .bearer)
    #expect(key == "sk-live")
    #expect(try secrets.secret(for: "openai") == "sk-live")
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
    let model = makeModel(events: [], error: error)
    model.selectProvider("openai")
    model.keyDraft = "sk-x"

    model.testConnection()
    await waitForResult(model)

    #expect(model.connection == .failed(.model(error)))
  }

  @Test func errorMessagesNeverShowTheKey() async {
    let model = makeModel(
      events: [], error: ModelError.badRequest(message: "Incorrect API key provided: sk-secret-9"))
    model.selectProvider("openai")
    model.keyDraft = "sk-secret-9"

    model.testConnection()
    await waitForResult(model)

    #expect(
      model.connection
        == .failed(.model(.badRequest(message: "Incorrect API key provided: ••••"))))
  }

  @Test func streamWithoutEventsIsAnEmptyResponse() async {
    let status = await SettingsModel.probe(
      ScriptedModel(events: [], error: nil), redacting: nil)

    #expect(status == .failed(.model(.emptyResponse)))
  }

  @Test func editingTheModelClearsTheResult() async {
    let model = makeModel()
    model.selectProvider("openai")
    model.keyDraft = "sk-x"
    model.testConnection()
    await waitForResult(model)

    model.update { $0.model.model = "gpt-5-nano" }

    #expect(model.connection == .idle)
  }

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
      ]
    for failure in failures {
      #expect(!failure.message.isEmpty, "\(failure)")
    }
  }
}
