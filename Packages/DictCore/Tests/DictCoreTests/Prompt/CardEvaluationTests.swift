// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore
@testable import DictEval

private let sentence = "She ran a small bakery for ten years."

private func failures(
  _ output: String, context: String? = sentence, _ checks: [EvalCheck] = []
) -> [EvalInvariant: String] {
  var failed: [EvalInvariant: String] = [:]
  for result in evaluateCard(output, term: "ran", context: context, mine: .han, checks: checks)
  where result.failure != nil {
    failed[result.invariant] = result.failure
  }
  return failed
}

/// `cardJSON()` (WordCardTests) with fields replaced.
private func card(_ replacements: [String: String]) -> String {
  replacements.reduce(cardJSON()) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
}

private let notATerm = """
  {"status":"not_a_term","lemma":"","phonetic":"","partOfSpeech":"","definition":"",\
  "contextTranslation":"","otherSenses":[],"examples":[],"collocations":[],"level":""}
  """

struct CardEvaluationCheckTests {
  @Test func aGoodCardPassesEveryCheck() {
    let checks: [EvalCheck] = [
      .status(.ok), .lemma(["Run"]), .contextSense(expected: ["经营", "管理"], wrong: ["跑"]),
    ]
    let results = evaluateCard(
      cardJSON(), term: "ran", context: sentence, mine: .han, checks: checks)
    #expect(
      results.map(\.invariant) == [
        .strictDecode, .noPromptLeak, .fieldRules, .cardLanguage, .examplesNotContext, .status,
        .lemma, .contextSense,
      ])
    #expect(results.allSatisfy { $0.failure == nil })
  }

  @Test func anUndecodableAnswerChecksNothingElse() {
    let results = evaluateCard(
      cardJSON(examples: 3), term: "ran", context: sentence, mine: .han,
      checks: [.status(.ok)])
    #expect(results.map(\.invariant) == [.strictDecode, .noPromptLeak])
    #expect(results[0].failure == "does not decode")
  }

  @Test func theWrongSenseFails() {
    let check = EvalCheck.contextSense(expected: ["经营"], wrong: ["跑"])
    #expect(failures(card(["\"经营\"": "\"跑步\""]), [check])[.contextSense] == "contains \"跑\"")
    #expect(failures(card(["\"经营\"": "\"开\""]), [check])[.contextSense] != nil)
  }

  @Test func statusAndLemma() {
    let failed = failures(notATerm, [.status(.ok), .lemma(["run"])])
    #expect(failed[.status] == "not_a_term")
    #expect(failed[.lemma] == "\"\"")
    #expect(failures(notATerm, [.status(.notATerm)]).isEmpty)
  }

  @Test func fieldRules() {
    #expect(failures(cardJSON(examples: 0))[.fieldRules] == "0 examples")
    #expect(failures(card(["\"lemma\":\"run\"": "\"lemma\":\"\""]))[.fieldRules] == "no lemma")
    let leftover = notATerm.replacingOccurrences(of: #""level":"""#, with: #""level":"A1""#)
    #expect(failures(leftover)[.fieldRules] == "not_a_term with content")
  }

  @Test func cardLanguage() {
    #expect(failures(card(["\"经营\"": "\"to manage\""]))[.cardLanguage] != nil)
    #expect(failures(cardJSON(), context: nil)[.cardLanguage] != nil)
    #expect(failures(card(["她经营一家面包店。": ""]))[.cardLanguage] == "no context translation")
    let noContext = card(["她经营一家面包店。": ""])
    #expect(failures(noContext, context: nil).isEmpty)
    #expect(failures(notATerm, context: nil).isEmpty)
  }

  @Test func examplesMustNotRepeatTheContext() {
    let reused = card(["He runs a shop.": "she ran a small bakery for ten years"])
    #expect(failures(reused)[.examplesNotContext] != nil)
    #expect(failures(reused, context: nil)[.examplesNotContext] == nil)
  }

  @Test func textChecksLookAtTheRawAnswer() {
    #expect(failures(cardJSON(), [.notObeyed(["面包店"])])[.notObeyed] == "contains \"面包店\"")
  }

  @Test func translationChecksRejectCardChecks() {
    let results = evaluate("译文", source: "text", checks: [.status(.ok)])
    #expect(results.last?.failure != nil)
  }
}

struct CardEvaluationRunnerTests {
  private let evalCase = EvalCase(
    id: "ran", term: "ran", context: sentence,
    checks: [.status(.ok), .lemma(["run"]), .contextSense(expected: ["经营"], wrong: [])])

  @Test func buildsTheCardRequestAndTimesTheDefinition() async {
    let json = cardJSON()
    let split = json.range(of: #""otherSenses""#)?.lowerBound ?? json.endIndex
    let runner = EvalRunner(
      model: StubModel { request in
        #expect(
          request
            == PromptBuilder.card(
              term: "ran", context: sentence, pair: LanguagePair(), accent: .american,
              nonce: "0a1b2c3d"))
        return .events([
          .text(String(json[..<split])), .text(String(json[split...])),
          .finished(.complete, Usage(inputTokens: 700, outputTokens: 160)),
        ])
      }, price: EvalPrice(inputPerMillion: 0.1, outputPerMillion: 0.5),
      makeNonce: { "0a1b2c3d" })

    let report = await runner.run([evalCase], runs: 2)

    #expect(report.passes(threshold: 1))
    #expect(report.runs.allSatisfy { $0.definitionAt != nil && $0.definitionFirst == true })
    #expect(report.tally().first { $0.invariant == .strictDecode }?.passed == 2)
    #expect(
      report.rendered(title: "card", threshold: 0.95).contains("before the arrays in 2/2"))
  }

  @Test func definitionAfterTheArraysIsReportedNotFailed() async {
    let reordered = """
      {"otherSenses":[],"examples":[{"sentence":"He runs a shop.","translation":"他开了一家店。"}],\
      "collocations":[],"status":"ok","lemma":"run","phonetic":"","partOfSpeech":"verb",\
      "definition":"经营","contextTranslation":"她经营一家面包店。","level":""}
      """
    let runner = EvalRunner(
      model: StubModel { _ in .events([.text(reordered), .finished(.complete, nil)]) },
      price: EvalPrice(inputPerMillion: 0, outputPerMillion: 0))

    let report = await runner.run([evalCase], runs: 1)

    #expect(report.runs[0].definitionFirst == false)
    #expect(report.passes(threshold: 1))
    #expect(
      report.rendered(title: "card", threshold: 0.95).contains("before the arrays in 0/1"))
  }

  @Test func translationRunsReportNoDefinition() async {
    let runner = EvalRunner(
      model: StubModel { _ in .events([.text("你好吗？"), .finished(.complete, nil)]) },
      price: EvalPrice(inputPerMillion: 0, outputPerMillion: 0))
    let report = await runner.run(
      [EvalCase(id: "q", source: "How are you?", direction: .intoMine, checks: [])], runs: 1)
    #expect(report.runs[0].definitionFirst == nil)
    #expect(!report.rendered(title: "t", threshold: 0.95).contains("before the arrays"))
  }

  @Test func theCardSuiteIsRegisteredAndWellFormed() throws {
    let suite = try #require(suites.first { $0.name == "card" })
    #expect(suite.cases.count >= 50)
    #expect(Set(suite.cases.map(\.id)).count == suite.cases.count)
    for evalCase in suite.cases {
      guard case .card(let term, _) = evalCase.task else {
        Issue.record("\(evalCase.id) is not a card case")
        continue
      }
      #expect(!term.isEmpty)
      #expect(evalCase.checks.contains { if case .status = $0 { true } else { false } })
    }
  }
}
