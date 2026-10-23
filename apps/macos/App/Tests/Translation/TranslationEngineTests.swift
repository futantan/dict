// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Synchronization
import Testing

@testable import DictApp

/// Streams scripted events, or fails, without any network.
private struct ScriptedModel: TextModel {
  var events: [StreamEvent] = []
  var error: (any Error)?

  func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, Error> {
    AsyncThrowingStream { continuation in
      for event in events { continuation.yield(event) }
      continuation.finish(throwing: error)
    }
  }
}

/// Stands in for Apple Translation and records the languages it was asked for.
private final class FakeApple: Translator {
  let result: Result<String, any Error>
  let calls = Mutex<[(Locale.Language?, Locale.Language)]>([])

  init(_ result: Result<String, any Error>) { self.result = result }

  func translate(_ text: String, from: Locale.Language?, to: Locale.Language)
    -> AsyncThrowingStream<String, Error>
  {
    calls.withLock { $0.append((from, to)) }
    let result = result
    return AsyncThrowingStream { continuation in
      switch result {
      case .success(let text):
        continuation.yield(text)
        continuation.finish()
      case .failure(let error):
        continuation.finish(throwing: error)
      }
    }
  }
}

private let chinese = Locale.Language(identifier: "zh-Hans")
private let english = Locale.Language(identifier: "en")
private let complete = StreamEvent.finished(.complete, nil)

@MainActor
private func states(
  model: ScriptedModel?, apple: FakeApple = FakeApple(.success("你好，世界")),
  availability: AppleTranslationAvailability = .installed, text: String = "Hello, world",
  direction: Direction = .intoMine
) async -> [PanelState] {
  let engine = TranslationEngine(
    model: model.map { ModelTranslator(model: $0) }, apple: apple,
    appleAvailability: { _, _ in availability })
  var states: [PanelState] = []
  await engine.translate(text, direction: direction, pair: LanguagePair()) { states.append($0) }
  return states
}

private func state(_ phase: PanelPhase, note: PanelNote? = nil) -> PanelState {
  PanelState(source: "Hello, world", phase: phase, note: note)
}

@MainActor
struct TranslationEngineTests {
  @Test func modelStreamsIntoGeneratingThenResult() async {
    let model = ScriptedModel(events: [.text("你好"), .text("，世界\n</source_text_1>"), complete])
    #expect(
      await states(model: model) == [
        state(.generating("")), state(.generating("你好")), state(.generating("你好，世界")),
        state(.result("你好，世界")),
      ])
  }

  @Test func discardedTextIsRetracted() async {
    let model = ScriptedModel(events: [.text("嗯"), .discardText, .text("你好"), complete])
    #expect(
      await states(model: model) == [
        state(.generating("")), state(.generating("嗯")), state(.generating("")),
        state(.generating("你好")), state(.result("你好")),
      ])
  }

  @Test func modelFailureFallsBackToAppleWithANote() async {
    let error = ModelError.network(code: -1009)
    let note = TranslationStrings.fallbackNote(error)
    let apple = FakeApple(.success("你好，世界"))
    let result = await states(
      model: ScriptedModel(events: [.text("你")], error: error), apple: apple)
    #expect(
      result == [
        state(.generating("")), state(.generating("你")), state(.generating(""), note: note),
        state(.result("你好，世界"), note: note),
      ])
    #expect(apple.calls.withLock { $0.map(\.1) } == [chinese])
  }

  @Test func missingKeyFallsBack() async {
    let note = TranslationStrings.fallbackNote(ModelError.missingKey)
    #expect(
      await states(model: ScriptedModel(error: ModelError.missingKey)).last
        == state(.result("你好，世界"), note: note))
  }

  @Test func modelFailureWithoutAppleShowsTheError() async {
    let error = ModelError.timedOut(.firstEvent)
    #expect(
      await states(model: ScriptedModel(error: error), availability: .unsupported) == [
        state(.generating("")), state(.failure(TranslationStrings.modelFailure(error))),
      ])
  }

  /// A cut-off translation is incomplete: shown with a note, never as a complete result.
  @Test(arguments: [AppleTranslationAvailability.installed, .notInstalled])
  func truncatedTranslationIsKeptWithANote(availability: AppleTranslationAvailability) async {
    let model = ScriptedModel(events: [.text("你好"), .finished(.truncated, nil)])
    #expect(
      await states(model: model, availability: availability).last
        == state(.partial("你好"), note: TranslationStrings.truncatedNote))
  }

  /// A stream that fails after text showed keeps that text, marked incomplete, with the
  /// reason and a way to try again; the text never turns into an error.
  @Test(arguments: [
    ModelTranslationError.interrupted as any Error, ModelError.network(code: -1005),
    ModelError.timedOut(.idle), ModelTranslationError.refused,
  ])
  func failureAfterTextKeepsItAsIncomplete(error: any Error) async throws {
    let model = ScriptedModel(events: [.text("你好\n"), .text("世界")], error: error)
    let result = await states(model: model, availability: .notInstalled)
    let note = TranslationStrings.incompleteNote(error)
    #expect(result.last == state(.partial("你好\n世界"), note: note))
    #expect(note.action?.id == TranslationStrings.retryAction)
    #expect(note.action?.isDefault == false)
    #expect(!result.contains { if case .failure = $0.phase { true } else { false } })
  }

  /// With Apple Translation's languages installed, the model's failure still falls back.
  @Test func failureAfterTextFallsBackWhenAppleIsInstalled() async {
    let error = ModelTranslationError.interrupted
    #expect(
      await states(model: ScriptedModel(events: [.text("你好")], error: error)).last
        == state(.result("你好，世界"), note: TranslationStrings.fallbackNote(error)))
  }

  /// Text retracted by `.discardText` was never the translation: a failure after it shows
  /// the error, as if nothing had arrived.
  @Test func failureAfterRetractedTextShowsTheError() async {
    let error = ModelTranslationError.interrupted
    let model = ScriptedModel(events: [.text("嗯"), .discardText], error: error)
    #expect(
      await states(model: model, availability: .notInstalled).last
        == state(.failure(TranslationStrings.modelFailure(error))))
  }

  @Test func withoutAModelAppleTranslates() async {
    let apple = FakeApple(.success("你好，世界"))
    #expect(
      await states(model: nil, apple: apple) == [
        state(.generating("")), state(.result("你好，世界")),
      ])
    #expect(apple.calls.withLock { $0.first?.1 } == chinese)
  }

  /// Without a model, languages that are merely supported count as missing: no download is
  /// ever offered, and the panel asks for a model.
  @Test(arguments: [AppleTranslationAvailability.notInstalled, .unsupported])
  func withoutAModelOrInstalledLanguagesAsksForAModel(availability: AppleTranslationAvailability)
    async
  {
    let apple = FakeApple(.success("你好，世界"))
    #expect(
      await states(model: nil, apple: apple, availability: availability) == [
        state(.needsSetup(TranslationStrings.needsModel))
      ])
    #expect(apple.calls.withLock { $0.isEmpty })
  }

  @Test(arguments: [AppleTranslationAvailability.notInstalled, .unsupported])
  func modelFailureWithoutInstalledLanguagesShowsTheError(
    availability: AppleTranslationAvailability
  ) async {
    let error = ModelError.network(code: -1009)
    let apple = FakeApple(.success("你好，世界"))
    #expect(
      await states(model: ScriptedModel(error: error), apple: apple, availability: availability)
        == [state(.generating("")), state(.failure(TranslationStrings.modelFailure(error)))])
    #expect(apple.calls.withLock { $0.isEmpty })
  }

  /// A missing or rejected key points to Settings: in the note under Apple Translation's
  /// result, or as the error's button.
  @Test(arguments: [ModelError.missingKey, .unauthorized])
  func keyProblemsOfferSettings(error: ModelError) async throws {
    let fallBack = await states(model: ScriptedModel(error: error)).last
    let note = try #require(fallBack?.note)
    #expect(note.action?.id == TranslationStrings.openSettingsAction)
    #expect(fallBack == state(.result("你好，世界"), note: note))

    let shown = await states(model: ScriptedModel(error: error), availability: .notInstalled)
    guard case .failure(let notice) = shown.last?.phase else {
      Issue.record("expected a failure, got \(String(describing: shown.last))")
      return
    }
    #expect(notice.actions.map(\.id) == [TranslationStrings.openSettingsAction])
  }

  @Test func otherModelFailuresOfferRetryNotSettings() {
    let error = ModelError.network(code: -1009)
    #expect(TranslationStrings.fallbackNote(error).action == nil)
    #expect(
      TranslationStrings.modelFailure(error).actions.map(\.id) == [TranslationStrings.retryAction])
  }

  /// When Apple Translation fails while standing in, the model's error is what to fix.
  @Test func failedFallbackShowsTheModelError() async {
    struct Broken: Error {}
    let error = ModelError.unauthorized
    #expect(
      await states(model: ScriptedModel(error: error), apple: FakeApple(.failure(Broken()))).last
        == state(.failure(TranslationStrings.modelFailure(error))))
  }

  /// Text in no recognizable language is checked as the pair's other language, never
  /// assumed installed.
  @Test func unrecognizedTextIsCheckedAgainstThePair() async {
    let checked = Mutex<[(Locale.Language, Locale.Language)]>([])
    let engine = TranslationEngine(
      model: nil, apple: FakeApple(.success("1234")),
      appleAvailability: { source, target in
        checked.withLock { $0.append((source, target)) }
        return .notInstalled
      })
    var states: [PanelState] = []
    await engine.translate("1234", direction: .intoMine, pair: LanguagePair()) {
      states.append($0)
    }
    #expect(checked.withLock { $0.map(\.0) } == [english])
    #expect(checked.withLock { $0.map(\.1) } == [chinese])
    #expect(states.map(\.phase) == [.needsSetup(TranslationStrings.needsModel)])
  }

  /// With a model the request starts at once: Apple Translation's languages are checked only
  /// when the model fails and a fallback is possible (measured 10–40 ms per press).
  @Test func aModelDoesNotWaitForAppleAvailability() async {
    let checks = Mutex(0)
    func engine(_ model: ScriptedModel) -> TranslationEngine {
      TranslationEngine(
        model: ModelTranslator(model: model), apple: FakeApple(.success("你好")),
        appleAvailability: { _, _ in
          checks.withLock { $0 += 1 }
          return .installed
        })
    }
    await engine(ScriptedModel(events: [.text("你好"), complete]))
      .translate("Hello", direction: .intoMine, pair: LanguagePair()) { _ in }
    #expect(checks.withLock { $0 } == 0)

    var states: [PanelState] = []
    await engine(ScriptedModel(error: ModelError.network(code: -1009)))
      .translate("Hello", direction: .intoMine, pair: LanguagePair()) { states.append($0) }
    #expect(checks.withLock { $0 } == 1)
    #expect(states.last?.phase == .result("你好"))
  }

  @Test func appleFailureIsShown() async throws {
    struct Broken: Error {}
    let result = await states(model: nil, apple: FakeApple(.failure(Broken())))
    let phase = try #require(TranslationStrings.appleFailure(Broken()))
    #expect(result.last == state(phase))
  }

  @Test func cancellingStopsUpdates() async {
    let engine = TranslationEngine(
      model: ModelTranslator(model: ScriptedModel(events: [.text("你好"), complete])),
      apple: FakeApple(.success("")), appleAvailability: { _, _ in .installed })
    var states: [PanelState] = []
    let task = Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      await engine.translate("Hello", direction: .intoMine, pair: LanguagePair()) {
        states.append($0)
      }
    }
    await task.value
    #expect(states.isEmpty)
  }
}

struct AppleLanguagesTests {
  @Test(arguments: [
    // (direction, detected, expected source, expected target)
    (Direction.intoMine, "en" as String?, "en" as String?, "zh-Hans"),
    (.intoMine, "fr", "fr", "zh-Hans"),
    (.intoMine, nil, nil, "zh-Hans"),
    (.intoLearning, "zh-Hans", "zh-Hans", "en"),
    (.undecided, "zh-Hans", "zh-Hans", "en"),
    (.undecided, "zh-Hant", "zh-Hant", "zh-Hans"),
    (.undecided, "en", "en", "zh-Hans"),
    (.undecided, nil, nil, "zh-Hans"),
  ])
  func languages(direction: Direction, detected: String?, source: String?, target: String) {
    let languages = appleLanguages(
      direction: direction, pair: LanguagePair(),
      detected: detected.map(Locale.Language.init(identifier:)))
    #expect(
      languages.source?.maximalIdentifier
        == source.map { Locale.Language(identifier: $0).maximalIdentifier })
    #expect(languages.target == Locale.Language(identifier: target))
  }

  @Test func recognizesTheDominantLanguage() {
    #expect(dominantLanguage(of: "The weather is lovely today.")?.languageCode == .english)
    #expect(dominantLanguage(of: "今天天气很好，我们去公园散步吧。")?.maximalIdentifier == "zh-Hans-CN")
    #expect(dominantLanguage(of: "1234") == nil)
  }
}

struct TranslationStringsTests {
  private func chinese(_ key: String) throws -> String {
    let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    return bundle.localizedString(forKey: key, value: "<missing>", table: "Translation")
  }

  @Test func fallbackNoteReadsInChinese() throws {
    let template = try chinese("The model failed (%@), so Apple Translation was used.")
    #expect(String(format: template, try chinese("network error")) == "模型出错（网络错误），已改用 Apple 翻译。")
  }

  @Test func everyFailureHasItsOwnReason() {
    let errors: [any Error] = [
      ModelError.missingKey, ModelError.unauthorized, ModelError.modelNotFound,
      ModelError.rateLimited(retryAfter: nil), ModelError.badRequest(message: ""),
      ModelError.server(status: 500), ModelError.network(code: -1009),
      ModelError.timedOut(.idle), ModelError.emptyResponse, ModelTranslationError.refused,
      ModelTranslationError.interrupted, ModelTranslationError.truncated,
      CocoaError(.featureUnsupported),
    ]
    #expect(Set(errors.map(TranslationStrings.modelFailureReason)).count == errors.count)
  }

  @Test func incompleteNoteReadsInChinese() throws {
    let template = try chinese("The translation is incomplete (%@).")
    #expect(
      String(format: template, try chinese("the connection was interrupted")) == "译文未完成（连接中断）。")
  }

  @Test func incompleteNoteOffersSettingsForKeyProblems() {
    #expect(
      TranslationStrings.incompleteNote(ModelError.unauthorized).action?.id
        == TranslationStrings.openSettingsAction)
  }

  @Test func cancellationShowsNothing() {
    #expect(TranslationStrings.appleFailure(CancellationError()) == nil)
  }
}
