// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Synchronization
import Testing

@testable import DictCore
@testable import DictEval

private let pair = LanguagePair()
private let source = "我们5月20日下午三点开会。"

private func failures(_ output: String, back: String?, checks: [EvalCheck] = [])
  -> [EvalInvariant: String]
{
  var failed: [EvalInvariant: String] = [:]
  for result in evaluateTranslateOut(
    output, back: back, source: source, pair: pair, checks: checks)
  {
    if let failure = result.failure { failed[result.invariant] = failure }
  }
  return failed
}

struct TranslateOutEvaluationTests {
  private let english = "We have a meeting at 3 p.m. on May 20."

  @Test func faithfulRoundTripPassesEveryCheck() {
    let results = evaluateTranslateOut(
      english, back: "我们5月20日下午3点开会。", source: source, pair: pair,
      checks: [.targetLanguage(.latin), .backKeeps(["开会"])])
    #expect(
      results.map(\.invariant) == [
        .noPromptLeak, .sameLineCount, .targetLanguage, .validates, .backCompleted,
        .backLanguage, .backMeaning,
      ])
    #expect(results.allSatisfy { $0.failure == nil })
  }

  @Test func validateIssuesAreReported() {
    #expect(failures(source, back: source)[.validates] == "languageMismatch, unchanged")
  }

  @Test func missingBackTranslationStopsTheBackChecks() {
    let failed = failures(english, back: nil)
    #expect(failed[.backCompleted] != nil)
    #expect(failed[.backMeaning] == nil)
  }

  @Test func backTranslationMustKeepNumbersCharactersAndKeyWords() {
    #expect(failures(english, back: "我们5月21日下午3点开会。")[.backMeaning] == "missing \"20\"")
    #expect(
      failures(english, back: "5月20日天气很好。")[.backMeaning]?.hasPrefix("Han overlap") == true)
    #expect(
      failures(english, back: "我们5月20日下午三点见面。", checks: [.backKeeps(["开会", "会议"])])[
        .backMeaning] == "none of \"开会\", \"会议\"")
    #expect(failures(english, back: "We meet on May 20 at 3.")[.backLanguage] != nil)
  }

  /// A live gpt-6-luna round trip: "3月份" went out as "March" and came back as "三月份".
  @Test func singleDigitMayComeBackAsAChineseNumeral() {
    let invoice = "附件是3月份的发票，金额共计12,800元，请查收。"
    let results = evaluateTranslateOut(
      "Attached is the invoice for March. The total amount is 12,800 yuan. Please review it.",
      back: "附件是三月份的发票。总金额为12,800元。请查阅。", source: invoice, pair: pair, checks: [])
    #expect(results.first { $0.invariant == .backMeaning }?.failure == nil)
    #expect(failures(english, back: "我们五月20日下午三点开会。")[.backMeaning] == nil)
  }

  @Test func runnerTranslatesOutThenBacktranslatesTheCleanedResult() async {
    let requests = Mutex<[ModelRequest]>([])
    let runner = EvalRunner(
      model: StubModel { request in
        let index = requests.withLock { requests in
          requests.append(request)
          return requests.count
        }
        let text = index == 1 ? "\"\(english)\"" : "我们5月20日下午3点开会。"
        return .events([.text(text), .finished(.complete, Usage(inputTokens: 10, outputTokens: 5))])
      }, price: EvalPrice(inputPerMillion: 1, outputPerMillion: 1), makeNonce: { "0a1b2c3d" })
    let evalCase = EvalCase(
      id: "meeting", translateOut: source, context: .mail, checks: [.targetLanguage(.latin)])

    let report = await runner.run([evalCase], runs: 1)

    #expect(
      requests.withLock { $0 } == [
        PromptBuilder.translateOut(source, pair: pair, context: .mail, nonce: "0a1b2c3d"),
        PromptBuilder.translation(english, into: pair.mine, nonce: "0a1b2c3d"),
      ])
    #expect(report.runs[0].output == english)
    #expect(report.runs[0].backTranslation == "我们5月20日下午3点开会。")
    #expect(report.runs[0].usage == Usage(inputTokens: 20, outputTokens: 10))
    #expect(report.passes(threshold: 1))
    #expect(report.rendered(title: "t", threshold: 1).contains("validates"))
  }

  @Test func failedForwardCallSkipsTheBackTranslation() async {
    let calls = Counter()
    let runner = EvalRunner(
      model: StubModel { _ in
        _ = calls.next()
        return .events([.text("We"), .finished(.truncated, nil)])
      }, price: EvalPrice(inputPerMillion: 1, outputPerMillion: 1))
    let report = await runner.run(
      [EvalCase(id: "x", translateOut: source, context: .chat, checks: [])], runs: 1)
    #expect(calls.next() == 1)
    #expect(report.runs[0].results.map(\.invariant) == [.completed])
  }

  @Test func theSuiteIsRegisteredAndWellFormed() throws {
    let suite = try #require(suites.first { $0.name == "translateOut" })
    #expect(suite.cases.count >= 20)
    #expect(Set(suite.cases.map(\.id)).count == suite.cases.count)
    for evalCase in suite.cases {
      guard case .translateOut(let text, _) = evalCase.task else {
        Issue.record("\(evalCase.id) is not a translate-out case")
        continue
      }
      #expect(writeAction(for: text, pair: pair) == .translateOut, "\(evalCase.id)")
      #expect(evalCase.checks.contains(.targetLanguage(.latin)))
    }
  }
}
