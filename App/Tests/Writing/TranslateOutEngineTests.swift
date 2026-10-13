// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Synchronization
import Testing

@testable import DictApp

/// Answers the translate-out request and the back-translation each with their own script,
/// without any network; records which requests it saw.
private final class TwoWayModel: TextModel {
  let forward: [StreamEvent]
  let forwardError: (any Error)?
  let back: [StreamEvent]
  let backError: (any Error)?
  let requests = Mutex<[String]>([])

  init(
    forward: [StreamEvent], forwardError: (any Error)? = nil, back: [StreamEvent] = [],
    backError: (any Error)? = nil
  ) {
    self.forward = forward
    self.forwardError = forwardError
    self.back = back
    self.backError = backError
  }

  func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, Error> {
    let isForward = (request.system + request.user).contains("as the writer's own message")
    requests.withLock { $0.append(isForward ? "forward" : "back") }
    let (events, error) = isForward ? (forward, forwardError) : (back, backError)
    return AsyncThrowingStream { continuation in
      for event in events { continuation.yield(event) }
      continuation.finish(throwing: error)
    }
  }
}

/// Stands in for Apple Translation: answers by target language, records the languages.
private final class FakeApple: Translator {
  let answers: [String: Result<String, any Error>]
  let calls = Mutex<[String]>([])

  init(_ answers: [String: Result<String, any Error>]) { self.answers = answers }

  func translate(_ text: String, from: Locale.Language?, to: Locale.Language)
    -> AsyncThrowingStream<String, Error>
  {
    let key = "\(from?.languageCode?.identifier ?? "?")>\(to.languageCode?.identifier ?? "?")"
    calls.withLock { $0.append(key) }
    let answer = answers[key] ?? .failure(CancellationError())
    return AsyncThrowingStream { continuation in
      switch answer {
      case .success(let text):
        continuation.yield(text)
        continuation.finish()
      case .failure(let error):
        continuation.finish(throwing: error)
      }
    }
  }
}

private let source = "我们明天下午三点开会。"
private let english = "We have a meeting at three tomorrow afternoon."
private let complete = StreamEvent.finished(.complete, nil)
private let forward: [StreamEvent] = [
  .text("We have a meeting"), .text(" at three tomorrow afternoon."), complete,
]
private let back: [StreamEvent] = [.text("我们明天下午\n三点开会。"), complete]

@MainActor
private func states(
  model: TwoWayModel?, apple: FakeApple = FakeApple([:]),
  availability: AppleTranslationAvailability = .notInstalled, text: String = source
) async -> [PanelState] {
  let engine = TranslateOutEngine(
    model: model.map { ModelTranslator(model: $0, makeNonce: { "n" }) }, apple: apple,
    appleAvailability: { _, _ in availability })
  var states: [PanelState] = []
  await engine.translateOut(text, pair: LanguagePair(), context: .chat) { states.append($0) }
  return states
}

private func out(_ translation: TranslateOut, note: PanelNote? = nil) -> PanelState {
  PanelState(source: source, phase: .translatedOut(translation), note: note)
}

@MainActor
struct TranslateOutEngineTests {
  /// The translation streams in, completes without issues, then the back-translation
  /// arrives on one line.
  @Test func streamsThenTranslatesBack() async {
    let model = TwoWayModel(forward: forward, back: back)
    let shown = await states(model: model)

    #expect(
      shown == [
        out(TranslateOut()),
        out(TranslateOut(text: "We have a meeting")),
        out(TranslateOut(text: english)),
        out(TranslateOut(text: english, isComplete: true)),
        out(
          TranslateOut(text: english, isComplete: true, backTranslation: .text("我们明天下午 三点开会。"))),
      ])
    #expect(model.requests.withLock { $0 } == ["forward", "back"])
  }

  /// The back-translation failing leaves the translation as it was, replaceable.
  @Test func aFailedBackTranslationOnlySaysSo() async {
    let model = TwoWayModel(forward: forward, backError: ModelError.network(code: -1009))
    let last = await states(model: model).last

    #expect(
      last == out(TranslateOut(text: english, isComplete: true, backTranslation: .unavailable)))
  }

  /// A result still in my language is complete but has issues, named once in the panel.
  @Test func anUntranslatedResultHasIssues() async {
    let model = TwoWayModel(forward: [.text(source), complete], back: back)
    let shown = await states(model: model)

    let complete = shown.compactMap { state -> TranslateOut? in
      if case .translatedOut(let translation) = state.phase, translation.isComplete {
        translation
      } else {
        nil
      }
    }
    #expect(complete.first?.issues == [.languageMismatch, .unchanged])
    #expect(complete.first?.shownIssues == [.unchanged])
  }

  /// A failed forward stream never asks for a back-translation.
  @Test func aFailedTranslationIsNotTranslatedBack() async {
    let model = TwoWayModel(forward: [], forwardError: ModelError.network(code: -1009))
    let shown = await states(model: model)

    #expect(
      shown.last
        == PanelState(
          source: source,
          phase: .failure(TranslationStrings.modelFailure(ModelError.network(code: -1009)))))
    #expect(model.requests.withLock { $0 } == ["forward"])
  }

  /// Cut off at the length limit: kept as partial, which never replaces.
  @Test func aTruncatedTranslationIsPartial() async {
    let model = TwoWayModel(forward: [.text("We have"), .finished(.truncated, nil)])
    let last = await states(model: model, availability: .installed).last

    #expect(
      last
        == PanelState(
          source: source, phase: .partial("We have"),
          note: TranslationStrings.partialNote(ModelTranslationError.truncated)))
  }

  /// A failing model falls back to Apple Translation, whose result is cleaned, validated and
  /// translated back by Apple Translation too.
  @Test func aFailedModelFallsBackToAppleTranslation() async {
    let error = ModelError.network(code: -1009)
    let model = TwoWayModel(forward: [], forwardError: error)
    let apple = FakeApple([
      "zh>en": .success("“\(english)”"), "en>zh": .success("我们明天下午三点开会。"),
    ])
    let shown = await states(model: model, apple: apple, availability: .installed)

    let note = TranslationStrings.fallbackNote(error)
    #expect(
      shown.suffix(3) == [
        out(TranslateOut(), note: note),
        out(TranslateOut(text: english, isComplete: true), note: note),
        out(
          TranslateOut(text: english, isComplete: true, backTranslation: .text("我们明天下午三点开会。")),
          note: note),
      ])
    #expect(apple.calls.withLock { $0 } == ["zh>en", "en>zh"])
  }

  @Test func withoutAModelAppleTranslationTranslatesOut() async {
    let apple = FakeApple([
      "zh>en": .success(english), "en>zh": .failure(CocoaError(.featureUnsupported)),
    ])
    let last = await states(model: nil, apple: apple, availability: .installed).last

    #expect(
      last == out(TranslateOut(text: english, isComplete: true, backTranslation: .unavailable)))
  }

  @Test func withoutAModelOrLanguagesAModelIsNeeded() async {
    let shown = await states(model: nil, availability: .notInstalled)

    #expect(
      shown == [PanelState(source: source, phase: .needsSetup(TranslationStrings.needsModel))])
  }

  /// Hiding the panel cancels the task: nothing more is reported, and no back-translation.
  @Test func cancellingStopsEverything() async {
    let model = TwoWayModel(forward: forward, back: back)
    let engine = TranslateOutEngine(
      model: ModelTranslator(model: model, makeNonce: { "n" }), apple: FakeApple([:]),
      appleAvailability: { _, _ in .notInstalled })
    let task = Task { @MainActor in
      var states: [PanelState] = []
      withUnsafeCurrentTask { $0?.cancel() }
      await engine.translateOut(source, pair: LanguagePair(), context: .other) {
        states.append($0)
      }
      return states
    }
    #expect(await task.value.isEmpty)
    #expect(!model.requests.withLock { $0 }.contains("back"))
  }
}
