// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

struct ModelCheckTests {
  private let chinese = Locale.Language(identifier: "zh-Hans")

  // MARK: - Requests

  @Test func translationCheckTranslatesASampleSentence() {
    let request = ModelCheck.translationRequest(into: chinese, nonce: "0badc0de")

    #expect(
      request == PromptBuilder.translation(ModelCheck.sample, into: chinese, nonce: "0badc0de"))
    #expect(request.output == .text)
  }

  /// The structured check uses the strict schema of a real operation, not a toy one.
  @Test func structuredCheckUsesTheProofreadSchema() {
    let request = ModelCheck.structuredOutputRequest(nonce: "0badc0de")

    #expect(request == PromptBuilder.proofread(ModelCheck.proofreadSample, nonce: "0badc0de"))
    guard case .jsonSchema(let name, _) = request.output else {
      Issue.record("Expected a JSON schema, got \(request.output)")
      return
    }
    #expect(name == "proofread")
  }

  // MARK: - Translation check

  private func translation(
    _ events: [StreamEvent], delay: Duration = .zero
  ) async throws -> TranslationCheck {
    let clock = ManualClock()
    let model = StubModel { _ in
      clock.advance(by: delay)
      return .events(events)
    }
    return try await ModelCheck.checkTranslation(
      model, into: chinese, clock: clock, makeNonce: { "0badc0de" })
  }

  @Test func translationReportsTheTimeToFirstContent() async throws {
    let result = try await translation(
      [.text("你好"), .finished(.complete, nil)], delay: .milliseconds(800))

    #expect(result == TranslationCheck(firstContent: .milliseconds(800), sawThinking: false))
  }

  @Test func thinkingDeltasAreNotContentButAreNoticed() async throws {
    let result = try await translation([
      .thinking, .thinking, .text("你好"), .finished(.complete, nil),
    ])

    #expect(result.sawThinking)
  }

  /// A lone `</think>` means the discarded text was thinking.
  @Test func discardedTextCountsAsThinking() async throws {
    let result = try await translation(
      [.text("hmm"), .discardText, .text("你好"), .finished(.complete, nil)])

    #expect(result.sawThinking)
  }

  @Test func onlyThinkingIsAnEmptyResponse() async {
    await #expect(throws: ModelError.emptyResponse) {
      try await translation([.thinking, .finished(.complete, nil)])
    }
  }

  @Test func blankTextIsAnEmptyResponse() async {
    await #expect(throws: ModelError.emptyResponse) {
      try await translation([.text(" \n"), .finished(.complete, nil)])
    }
  }

  @Test func modelErrorsPassThrough() async {
    let model = StubModel { _ in .failure(.modelNotFound) }

    await #expect(throws: ModelError.modelNotFound) {
      try await ModelCheck.checkTranslation(model, into: chinese)
    }
  }

  // MARK: - Structured output check

  private func structured(_ events: [StreamEvent]) async throws -> Bool {
    try await ModelCheck.checkStructuredOutput(StubModel { _ in .events(events) })
  }

  @Test func strictJSONPasses() async throws {
    let edits = #"{"edits":[{"kind":"grammar","wrong":"She go","right":"She went"}]}"#

    #expect(try await structured([.text(edits), .finished(.complete, nil)]) == false)
    #expect(try await structured([.thinking, .text(#"{"edits":[]}"#), .finished(.complete, nil)]))
  }

  /// Only the shape is checked: edits that don't fit the sample are still valid output.
  @Test func editsThatDoNotApplyStillPass() async throws {
    let edits = #"{"edits":[{"kind":"spelling","wrong":"absent","right":"x"}]}"#

    #expect(try await structured([.text(edits), .finished(.complete, nil)]) == false)
  }

  @Test(arguments: [
    (
      [StreamEvent.text("Sure! Here are the mistakes."), .finished(.complete, nil)],
      ProofreadError.malformed
    ),
    (
      [.text(#"{"edits":[{"kind":"typo","wrong":"a","right":"b"}]}"#), .finished(.complete, nil)],
      .malformed
    ),
    ([.text(#"{"edits":["#), .finished(.truncated, nil)], .truncated),
    ([.finished(.refused, nil)], .refused),
    ([.text(#"{"edits":[]}"#)], .interrupted),
  ])
  func badAnswersFail(events: [StreamEvent], expected: ProofreadError) async {
    await #expect(throws: expected) { try await structured(events) }
  }

  @Test func structuredModelErrorsPassThrough() async {
    let model = StubModel { _ in .failure(.badRequest(message: "response_format")) }

    await #expect(throws: ModelError.badRequest(message: "response_format")) {
      try await ModelCheck.checkStructuredOutput(model)
    }
  }

  // MARK: - Thinking hint

  @Test(arguments: [
    (Duration?.some(.milliseconds(800)), false, false),
    (.some(.seconds(3)), false, false),
    (.some(.milliseconds(3001)), false, true),
    (.some(.milliseconds(500)), true, true),
    (nil, true, true),
    (nil, false, false),
  ])
  func thinkingHint(firstContent: Duration?, sawThinking: Bool, expected: Bool) {
    #expect(ModelCheck.isThinking(firstContent: firstContent, sawThinking: sawThinking) == expected)
  }
}
