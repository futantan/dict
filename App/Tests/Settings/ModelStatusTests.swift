// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Testing

@testable import DictApp

/// What the model settings say in each state, in the onboarding's form and the settings
/// page's cards alike.
@MainActor
struct ModelStatusTests {
  private let presets = (try? ProviderPreset.all()) ?? []

  private func preset(_ id: String) throws -> ProviderPreset {
    try #require(presets.first { $0.id == id })
  }

  private func model(_ preferences: ModelPreferences, key: String? = nil) throws -> SettingsModel {
    let suite = "ModelStatusTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    PreferencesStore(defaults: defaults).save(Preferences(model: preferences))
    var secrets: [String: String] = [:]
    if let key, let id = preferences.providerID { secrets[id] = key }
    return SettingsModel(defaults: defaults, secrets: InMemorySecretStore(secrets))
  }

  @Test func beforeATestThereIsANoteAndNoPill() {
    #expect(ModelStatus.connection(.idle).kind == .note)
    #expect(ModelStatus.summary(.idle) == nil)
  }

  @Test func aRunningTestIsBusyInBothPlaces() {
    let running = ConnectionStatus.checked(ConnectionReport(translation: .running))
    #expect(ModelStatus.connection(running).kind == .busy)
    #expect(ModelStatus.summary(running)?.kind == .busy)
  }

  @Test func aPassedTestShowsTheTimeToTheFirstWords() {
    let passed = ConnectionStatus.checked(.translated(after: .milliseconds(840)))
    #expect(ModelStatus.connection(passed).kind == .success)
    let summary = ModelStatus.summary(passed)
    #expect(summary?.kind == .success)
    #expect(summary?.text.contains("0.8") == true)
  }

  @Test func aThinkingModelPassesWithAWarning() {
    let slow = ConnectionStatus.checked(
      .translated(after: .milliseconds(4200), sawThinking: true))
    #expect(ModelStatus.connection(slow).kind == .warning)
    #expect(ModelStatus.summary(slow)?.kind == .warning)
  }

  @Test func aFailedCheckIsAFailure() {
    let failed = ConnectionStatus.checked(.failed(.model(.unauthorized)))
    #expect(ModelStatus.connection(failed).kind == .failure)
    #expect(ModelStatus.summary(failed)?.kind == .failure)
  }

  /// No request was sent: the reason may be long, so it is a line, not a pill.
  @Test func aTestThatCouldNotStartHasNoPill() {
    let failed = ConnectionStatus.failed(.setup(.missingModel))
    #expect(ModelStatus.connection(failed).kind == .failure)
    #expect(ModelStatus.summary(failed) == nil)
  }

  @Test func aFailedTranslationSkipsTheOtherChecks() {
    let checks = ModelStatus.checks(
      .failed(.model(.modelNotFound)), isCustom: false, hasListedModels: true)
    #expect(checks.map(\.state) == [.failed, .waiting, .waiting])
    // The message and the hint to choose a listed model.
    #expect(checks[0].details.count == 2)
    #expect(checks[1].details == checks[2].details)
  }

  @Test func onlyACustomProviderIsToldToTryAnotherJSONMode() {
    let report = ConnectionReport.translated(
      after: .milliseconds(900), structuredOutput: .failed(.structuredOutput(.malformed)))
    let custom = ModelStatus.checks(report, isCustom: true, hasListedModels: false)
    let openAI = ModelStatus.checks(report, isCustom: false, hasListedModels: false)
    #expect(custom[1].details.count == 2)
    #expect(openAI[1].details.count == 1)
  }

  @Test func ollamaWithNoModelsSaysHowToGetOne() throws {
    let line = ModelStatus.modelList(.loaded([]), preset: try preset("ollama"))
    #expect(line.kind == .warning)
    #expect(line.text.contains("ollama pull"))
    #expect(ModelStatus.modelList(.loaded(["a"]), preset: try preset("ollama")).kind == .note)
  }

  @Test func anEmptyKeyOffersTheProvidersKeyPage() throws {
    let openAI = try preset("openai")
    let note = ModelStatus.fieldsNote(
      try model(ModelPreferences(providerID: "openai")), preset: openAI)
    #expect(note == .keyLink("Get an API key from OpenAI", try #require(openAI.keyHelpURL)))
    let withKey = try model(ModelPreferences(providerID: "openai"), key: "sk-test")
    #expect(ModelStatus.fieldsNote(withKey, preset: openAI) == nil)
  }

  @Test func aPlainHTTPBaseURLIsAWarning() throws {
    let custom = try model(
      ModelPreferences(providerID: "custom", model: "m", baseURL: "http://example.com/v1"))
    guard case .warning = ModelStatus.fieldsNote(custom, preset: try preset("custom")) else {
      Issue.record("expected a warning")
      return
    }
  }
}
