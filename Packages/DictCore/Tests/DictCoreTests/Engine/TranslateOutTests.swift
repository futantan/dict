// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Synchronization
import Testing

@testable import DictCore

private let completed = StreamEvent.finished(.complete, Usage(inputTokens: 1, outputTokens: 1))

/// Every element of a stream, then how it ended.
private struct Outcome: Equatable {
  var elements: [String] = []
  var error: String?
}

private func collect(_ stream: AsyncThrowingStream<String, Error>) async -> Outcome {
  var outcome = Outcome()
  do {
    for try await element in stream { outcome.elements.append(element) }
  } catch {
    outcome.error = String(describing: error)
  }
  return outcome
}

private func translator(_ events: [StreamEvent]) -> ModelTranslator {
  ModelTranslator(model: StubModel { _ in .events(events) }, makeNonce: { "0badc0de" })
}

struct TranslateOutTests {
  private let pair = LanguagePair()

  @Test func sendsTheTranslateOutPromptWithTheAppContext() async {
    let requests = Mutex<[ModelRequest]>([])
    let model = StubModel { request in
      requests.withLock { $0.append(request) }
      return .events([.text("See you."), completed])
    }
    let translator = ModelTranslator(model: model, makeNonce: { "0badc0de" })
    _ = await collect(translator.translateOut("回头见。", pair: pair, context: .chat))
    _ = await collect(translator.backTranslate("See you.", pair: pair))
    #expect(
      requests.withLock { $0 } == [
        PromptBuilder.translateOut("回头见。", pair: pair, context: .chat, nonce: "0badc0de"),
        PromptBuilder.translation("See you.", into: pair.mine, nonce: "0badc0de"),
      ])
  }

  @Test func everyElementIsCleanedUpAndTheLastIsTheResult() async {
    let outcome = await collect(
      translator([.text("Translation: \"See"), .text(" you.\""), completed])
        .translateOut("回头见。\n", pair: pair, context: .chat))
    #expect(outcome.elements.last == "See you.\n")
    #expect(outcome.elements.allSatisfy { !$0.hasPrefix("Translation:") })
    #expect(outcome.error == nil)
  }

  @Test func incompleteForwardStreamThrowsAfterTheText() async {
    let outcome = await collect(
      translator([.text("See"), .finished(.truncated, nil)])
        .translateOut("回头见。", pair: pair, context: .other))
    #expect(outcome == Outcome(elements: ["See"], error: "truncated"))
  }

  @Test func blankAnswerIsAnEmptyResponse() async {
    let outcome = await collect(
      translator([.text("  "), completed]).translateOut("回头见。", pair: pair, context: .mail))
    #expect(outcome.error == "emptyResponse")
  }

  @Test func backTranslationComesOnOneLine() async {
    let outcome = await collect(
      translator([.text("第一段。\n\n"), .text("第二段。"), completed])
        .backTranslate("First.\n\nSecond.", pair: pair))
    #expect(outcome.elements.last == "第一段。 第二段。")
    #expect(outcome.error == nil)
  }

  @Test func oneLineJoinsEveryKindOfBreak() {
    #expect(oneLine(" a \r\n b\n\n\tc ") == "a b c")
    #expect(oneLine("abc") == "abc")
  }
}
