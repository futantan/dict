// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Synchronization
import Testing

@testable import DictCore

private let chinese = Locale.Language(identifier: "zh-Hans")
private let english = Locale.Language(identifier: "en")

/// What a translation stream produced: every element, then how it ended.
private struct Outcome: Equatable {
  var elements: [String] = []
  var error: ModelTranslationError?
  var otherError: String?
}

private func collect(_ stream: AsyncThrowingStream<String, Error>) async -> Outcome {
  var outcome = Outcome()
  do {
    for try await element in stream { outcome.elements.append(element) }
  } catch let error as ModelTranslationError {
    outcome.error = error
  } catch {
    outcome.otherError = String(describing: error)
  }
  return outcome
}

private func translator(_ events: [StreamEvent]) -> ModelTranslator {
  ModelTranslator(model: StubModel { _ in .events(events) }, makeNonce: { "0badc0de" })
}

private let completed = StreamEvent.finished(.complete, Usage(inputTokens: 1, outputTokens: 1))

struct ModelTranslationTests {
  @Test func textAccumulatesAndDiscardStartsOver() {
    var translation = ModelTranslation(source: "Hello")
    translation.apply(.thinking)
    translation.apply(.text("思考"))
    translation.apply(.discardText)
    translation.apply(.text("你"))
    translation.apply(.text("好"))
    #expect(translation.text == "你好")
    #expect(translation.finish == nil)
    translation.apply(completed)
    #expect(translation.finish == .complete)
    #expect(translation.text == "你好")
  }

  @Test func streamingHoldsBackAndFinishingDropsTheAddedTag() {
    var translation = ModelTranslation(source: "Hi <source_text>")
    translation.apply(.text("你好 <source_text>\n</source_text_0badc0de"))
    #expect(translation.text == "你好 <source_text>")
    translation.apply(.text(">"))
    #expect(translation.text == "你好 <source_text>")
    translation.apply(completed)
    #expect(translation.text == "你好 <source_text>")
  }

  @Test func finishingKeepsATagTheSourceHas() {
    var translation = ModelTranslation(source: "<b>bold\n</b>")
    translation.apply(.text("<b>粗体\n</b>"))
    #expect(translation.text == "<b>粗体")
    translation.apply(completed)
    #expect(translation.text == "<b>粗体\n</b>")
  }
}

struct ModelTranslatorTests {
  @Test func yieldsEachChangeOfTheCleanedText() async {
    let outcome = await collect(
      translator([.thinking, .text("你"), .text("好"), .text("\n</x>"), completed])
        .translate("Hello", from: english, to: chinese))
    #expect(outcome == Outcome(elements: ["你", "你好"]))
  }

  @Test func discardedTextIsRetracted() async {
    let outcome = await collect(
      translator([.text("想一想"), .discardText, .text("你好"), completed])
        .translate("Hello", from: nil, to: chinese))
    #expect(outcome == Outcome(elements: ["想一想", "", "你好"]))
  }

  @Test func usesTheDecidedDirectionPrompt() async {
    let requests = Mutex<[ModelRequest]>([])
    let model = StubModel { request in
      requests.withLock { $0.append(request) }
      return .events([.text("Hi"), completed])
    }
    let translator = ModelTranslator(model: model, makeNonce: { "0badc0de" })
    _ = await collect(translator.translate("你好", from: chinese, to: english))
    _ = await collect(translator.translate("你好", direction: .undecided, pair: LanguagePair()))
    #expect(
      requests.withLock { $0 } == [
        PromptBuilder.translation("你好", into: english, nonce: "0badc0de"),
        PromptBuilder.translationBetween("你好", pair: LanguagePair(), nonce: "0badc0de"),
      ])
  }

  @Test(arguments: [
    (FinishReason.truncated, ModelTranslationError.truncated),
    (.refused, .refused),
    (.unknown, .interrupted),
  ])
  func incompleteFinishThrowsAfterTheText(reason: FinishReason, error: ModelTranslationError)
    async
  {
    let outcome = await collect(
      translator([.text("你好"), .finished(reason, nil)])
        .translate("Hello", from: nil, to: chinese))
    #expect(outcome == Outcome(elements: ["你好"], error: error))
  }

  @Test func streamWithoutFinishIsInterrupted() async {
    let outcome = await collect(
      translator([.text("你")]).translate("Hello", from: nil, to: chinese))
    #expect(outcome == Outcome(elements: ["你"], error: .interrupted))
  }

  @Test func completeButEmptyIsAnEmptyResponse() async {
    let outcome = await collect(
      translator([.text("  \n"), completed]).translate("Hello", from: nil, to: chinese))
    #expect(outcome.elements == ["  \n"])
    #expect(outcome.otherError == String(describing: ModelError.emptyResponse))
  }

  @Test func modelErrorsPassThrough() async {
    let model = StubModel { _ in .failure(.network(code: -1009)) }
    let outcome = await collect(
      ModelTranslator(model: model).translate("Hello", from: nil, to: chinese))
    #expect(outcome.elements.isEmpty)
    #expect(outcome.otherError == String(describing: ModelError.network(code: -1009)))
  }

  @Test func cancellingTheConsumerCancelsTheModelStream() async throws {
    let cancelled = Mutex(false)
    let model = HangingModel(onCancel: { cancelled.withLock { $0 = true } })
    let task = Task {
      await collect(ModelTranslator(model: model).translate("Hello", from: nil, to: chinese))
    }
    try await eventually { model.started.withLock { $0 } }
    task.cancel()
    _ = await task.value
    try await eventually { cancelled.withLock { $0 } }
  }
}

/// Yields one delta, then waits until cancelled.
private final class HangingModel: TextModel {
  let started = Mutex(false)
  let onCancel: @Sendable () -> Void

  init(onCancel: @escaping @Sendable () -> Void) { self.onCancel = onCancel }

  func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, Error> {
    AsyncThrowingStream { continuation in
      continuation.yield(.text("你"))
      started.withLock { $0 = true }
      continuation.onTermination = { [onCancel] _ in onCancel() }
    }
  }
}
