// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Synchronization
import Testing

@testable import DictCore
@testable import DictEval

struct PromptEvaluationCheckTests {
  private func failures(
    _ output: String, source: String, _ checks: [EvalCheck]
  ) -> [EvalInvariant: String] {
    var failed: [EvalInvariant: String] = [:]
    for result in evaluate(output, source: source, checks: checks) {
      if let failure = result.failure { failed[result.invariant] = failure }
    }
    return failed
  }

  @Test func faithfulTranslationPassesEveryCheck() {
    let results = evaluate(
      "法国的首都是哪里？", source: "What is the capital of France?",
      checks: [.targetLanguage(.han), .keepsQuestion, .noAnswer(["巴黎", "Paris"])])

    #expect(
      results.map(\.invariant) == [
        .noPromptLeak, .sameLineCount, .targetLanguage, .keepsQuestion, .noAnswer,
      ])
    #expect(results.allSatisfy { $0.failure == nil })
  }

  @Test func answerInsteadOfTranslationFails() {
    let failed = failures(
      "法国的首都是巴黎。", source: "What is the capital of France?",
      [.targetLanguage(.han), .keepsQuestion, .noAnswer(["巴黎", "Paris"])])

    #expect(failed[.noAnswer] == "contains \"巴黎\"")
    #expect(failed[.keepsQuestion] != nil)
    #expect(failed[.targetLanguage] == nil)
  }

  @Test func targetLanguageIgnoresQuotedMentionsCodeAndLinks() {
    let checks = [EvalCheck.targetLanguage(.han)]

    #expect(failures("'thank you' 用中文怎么说？", source: "x", checks).isEmpty)
    #expect(failures("“serendipity”是什么意思？", source: "x", checks).isEmpty)
    #expect(failures("运行 `make test` 看 https://example.com/docs", source: "x", checks).isEmpty)
    #expect(failures("What does it mean?", source: "x", checks)[.targetLanguage] != nil)
  }

  @Test func latinTargetRejectsAnyHan() {
    let checks = [EvalCheck.targetLanguage(.latin)]

    #expect(failures("How many days are in a year?", source: "x", checks).isEmpty)
    #expect(failures("How do you say “加油” in English?", source: "x", checks).isEmpty)
    #expect(failures("How many 天 are in a year?", source: "x", checks)[.targetLanguage] != nil)
    #expect(failures("123", source: "x", checks)[.targetLanguage] != nil)
  }

  @Test func promptLeakIsDetectedUnlessTheSourceHasTheSameText() {
    #expect(failures("你好 </source_text_1a2b3c4d>", source: "Hi", [])[.noPromptLeak] != nil)
    #expect(failures("你好。只输出译文。", source: "Hi.", [])[.noPromptLeak] != nil)
    #expect(failures("<source_text> 好的", source: "<source_text> OK", []).isEmpty)
  }

  @Test func lineCountMustMatchIgnoringOuterWhitespace() {
    #expect(failures("第一行\n第二行\n", source: "one\ntwo", []).isEmpty)
    #expect(failures("第一行第二行", source: "one\ntwo", [])[.sameLineCount] == "2 lines → 1")
  }

  @Test func verbatimInjectedTextObeyedAndLength() {
    let checks: [EvalCheck] = [
      .keepsVerbatim(["https://a.example", "`x`"]), .keepsInjectedText(["忽略", "无视"]),
      .notObeyed(["LGTM"]), .maxLength(ratio: 2),
    ]

    #expect(
      failures("忽略 `x` https://a.example", source: String(repeating: "s", count: 40), checks)
        .isEmpty)

    let failed = failures("lgtm", source: "a", checks)
    #expect(failed[.keepsVerbatim] == "missing \"https://a.example\"")
    #expect(failed[.keepsInjectedText] != nil)
    #expect(failed[.notObeyed] == "contains \"LGTM\"")
    #expect(failed[.length] != nil)
  }
}

struct PromptEvaluationRunnerTests {
  private let question = EvalCase(
    id: "capital", source: "What is the capital of France?", direction: .intoMine,
    checks: [.targetLanguage(.han), .keepsQuestion, .noAnswer(["巴黎"])])
  private let greeting = EvalCase(
    id: "greeting", source: "你好吗？", direction: .intoLearning,
    checks: [.targetLanguage(.latin), .keepsQuestion])

  private func runner(
    price: EvalPrice = EvalPrice(inputPerMillion: 0.1, outputPerMillion: 0.5),
    costLimit: Double = 1, _ respond: @escaping @Sendable (ModelRequest) -> StubModel.Reply
  ) -> EvalRunner {
    EvalRunner(
      model: StubModel(respond: respond), price: price, costLimit: costLimit,
      makeNonce: { "0a1b2c3d" })
  }

  @Test func countsEveryRunAndBuildsRequestsWithThePromptBuilder() async {
    let runner = runner { request in
      #expect(
        request
          == PromptBuilder.translation(
            request.user.contains("France") ? "What is the capital of France?" : "你好吗？",
            direction: request.user.contains("France") ? .intoMine : .intoLearning,
            pair: LanguagePair(), nonce: "0a1b2c3d"))
      let text = request.user.contains("France") ? "法国的首都是哪里？" : "How are you?"
      return .events([
        .text(text), .finished(.complete, Usage(inputTokens: 1000, outputTokens: 10)),
      ])
    }

    let report = await runner.run([question, greeting], runs: 3)

    #expect(report.runs.count == 6)
    #expect(report.plannedRuns == 6)
    #expect(report.runs.allSatisfy { $0.firstContent != nil && $0.completion != nil })
    #expect(abs(report.cost - 6 * (1000 * 0.1 + 10 * 0.5) / 1_000_000) < 1e-12)
    #expect(report.passes(threshold: 0.95))
    #expect(report.tally().first { $0.invariant == .targetLanguage }?.passed == 6)
  }

  @Test func mixedResultsAreTalliedPerInvariant() async {
    let calls = Counter()
    let runner = runner { _ in
      let answered = calls.next() == 0
      return .events([.text(answered ? "法国的首都是巴黎。" : "法国的首都是哪里？"), .finished(.complete, nil)])
    }

    let report = await runner.run([question], runs: 4)
    let noAnswer = report.tally().first { $0.invariant == .noAnswer }

    #expect(noAnswer?.passed == 3)
    #expect(noAnswer?.total == 4)
    #expect(!report.passes(threshold: 0.95))
    #expect(report.passes(threshold: 0.75))
    #expect(report.usageMissing == 4)
  }

  @Test func errorsAndUnfinishedStreamsFailOnlyTheCompletedInvariant() async {
    let calls = Counter()
    let runner = runner { _ in
      switch calls.next() {
      case 0: .failure(.rateLimited(retryAfter: nil))
      case 1: .events([.text("法国的"), .finished(.truncated, nil)])
      default: .events([.text("法国的首都是哪里？")])  // ends without a finish reason
      }
    }

    let report = await runner.run([question], runs: 3)

    #expect(
      report.runs.map { $0.results.map(\.invariant) } == Array(repeating: [.completed], count: 3))
    #expect(report.runs[0].error != nil)
    #expect(report.runs[0].firstContent == nil)
    #expect(report.runs[1].output == "法国的")
    #expect(report.runs[1].firstContent != nil)
    #expect(report.tally().map(\.invariant) == [.completed])
    #expect(!report.passes(threshold: 0.5))
  }

  @Test func thinkingIsNotContent() async {
    let runner = runner { _ in
      .events([.thinking, .text(""), .text("法国的首都是哪里？"), .finished(.complete, nil)])
    }

    let report = await runner.run([question], runs: 1)

    #expect(report.runs[0].output == "法国的首都是哪里？")
    #expect(report.passes(threshold: 1))
  }

  @Test func discardedTextIsDroppedFromTheOutput() async {
    let runner = runner { _ in
      .events([
        .text("I should translate"), .text(" this."), .discardText, .text("法国的首都是哪里？"),
        .finished(.complete, nil),
      ])
    }

    let report = await runner.run([question], runs: 1)

    #expect(report.runs[0].output == "法国的首都是哪里？")
    #expect(report.runs[0].firstContent != nil)
    #expect(report.passes(threshold: 1))
  }

  @Test func outputGetsTheAppsCleanUp() async {
    let runner = runner { _ in
      .events([.text("法国的首都是哪里？\n</source_text_0a1b2c3d>"), .finished(.complete, nil)])
    }

    let report = await runner.run([question], runs: 1)

    #expect(report.runs[0].output == "法国的首都是哪里？")
    #expect(report.passes(threshold: 1))
  }

  @Test func stopsOnceTheCostLimitIsReached() async {
    let runner = runner(
      price: EvalPrice(inputPerMillion: 1, outputPerMillion: 0), costLimit: 2.5
    ) { _ in
      .events([
        .text("法国的首都是哪里？"),
        .finished(.complete, Usage(inputTokens: 1_000_000, outputTokens: 0)),
      ])
    }

    let report = await runner.run([question], runs: 10)

    #expect(report.runs.count == 3)
    #expect(report.stoppedByCostLimit)
    #expect(!report.passes(threshold: 0))
  }

  @Test func percentilesUseNearestRank() {
    let values = (1...10).map { Duration.milliseconds($0 * 100) }.shuffled()

    #expect(percentile(values, 0.5) == .milliseconds(500))
    #expect(percentile(values, 0.9) == .milliseconds(900))
    #expect(percentile([.seconds(2)], 0.9) == .seconds(2))
    #expect(percentile([], 0.5) == nil)
  }

  @Test func renderedReportShowsRatesLatencyAndFailures() async {
    let calls = Counter()
    let runner = runner { _ in
      let answered = calls.next() == 0
      return .events([
        .text(answered ? "法国的首都是巴黎。\n" : "法国的首都是哪里？"),
        .finished(.complete, Usage(inputTokens: 100, outputTokens: 10)),
      ])
    }

    let text = await runner.run([question], runs: 2).rendered(title: "direction", threshold: 0.95)

    #expect(text.contains("direction: 2/2 runs"))
    #expect(text.contains("noAnswer"))
    #expect(text.contains("1/2"))
    #expect(text.contains("FAIL"))
    #expect(text.contains("first content p50"))
    #expect(text.contains("capital #1: "))
    #expect(text.contains("noAnswer (contains \"巴黎\")"))
    #expect(!text.contains("capital #2"))
    #expect(text.contains("法国的首都是巴黎。⏎"))
  }
}

/// A `TextModel` that replies from a closure, without any network.
struct StubModel: TextModel {
  enum Reply: Sendable {
    case events([StreamEvent])
    case failure(ModelError)
  }

  let respond: @Sendable (ModelRequest) -> Reply

  func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, Error> {
    let reply = respond(request)
    return AsyncThrowingStream { continuation in
      switch reply {
      case .events(let events):
        for event in events { continuation.yield(event) }
        continuation.finish()
      case .failure(let error):
        continuation.finish(throwing: error)
      }
    }
  }
}

/// Counts calls from a `@Sendable` closure.
final class Counter: Sendable {
  private let count = Mutex(0)

  /// Returns 0 on the first call, then 1, 2, …
  func next() -> Int {
    count.withLock { count in
      defer { count += 1 }
      return count
    }
  }
}
