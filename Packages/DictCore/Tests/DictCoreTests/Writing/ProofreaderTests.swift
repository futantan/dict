// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Synchronization
import Testing

@testable import DictCore

private let completed = StreamEvent.finished(.complete, Usage(inputTokens: 1, outputTokens: 1))

private func proofreader(_ reply: StubModel.Reply) -> Proofreader {
  Proofreader(model: StubModel { _ in reply }, makeNonce: { "0badc0de" })
}

/// The corrected text, or the error's description.
private func outcome(_ reply: StubModel.Reply, source: String) async -> String {
  do {
    return try await proofreader(reply).proofread(source).text
  } catch {
    return "error: \(error)"
  }
}

struct ProofreaderTests {
  @Test func appliesTheStreamedEditList() async throws {
    let events: [StreamEvent] = [
      .thinking, .text(#"{"edits":[{"kind":"spelling","#),
      .text(#""wrong":"teh","right":"the"}]}"#),
      completed,
    ]
    let applied = try await proofreader(.events(events)).proofread("teh cat")
    #expect(applied.text == "the cat")
  }

  @Test func anEmptyListMeansNoMistakes() async throws {
    let applied = try await proofreader(.events([.text(#"{"edits":[]}"#), completed]))
      .proofread("Fine.")
    #expect(applied.changeCount == 0)
  }

  @Test func discardedTextIsNotParsed() async throws {
    let events: [StreamEvent] = [
      .text("thinking out loud"), .discardText, .text(#"{"edits":[]}"#), completed,
    ]
    #expect(try await proofreader(.events(events)).proofread("Fine.").changeCount == 0)
  }

  @Test func onlyACompleteAnswerIsUsed() async {
    let json = StreamEvent.text(#"{"edits":[]}"#)
    #expect(
      await outcome(.events([json, .finished(.truncated, nil)]), source: "a")
        == "error: truncated")
    #expect(
      await outcome(.events([json, .finished(.refused, nil)]), source: "a") == "error: refused")
    #expect(await outcome(.events([json]), source: "a") == "error: interrupted")
  }

  @Test func badEditsAndBadJSONFail() async {
    let notFound = StreamEvent.text(#"{"edits":[{"kind":"spelling","wrong":"x","right":"y"}]}"#)
    #expect(
      await outcome(.events([notFound, completed]), source: "a")
        == "error: edits(DictCore.EditError.notFound(index: 0))")
    #expect(await outcome(.events([.text("nope"), completed]), source: "a") == "error: malformed")
  }

  @Test func modelErrorsPassThrough() async {
    #expect(await outcome(.failure(.unauthorized), source: "a") == "error: unauthorized")
  }

  @Test func sendsTheProofreadPrompt() async throws {
    let seen = SeenRequest()
    let model = StubModel { request in
      seen.set(request)
      return .events([.text(#"{"edits":[]}"#), completed])
    }
    _ = try await Proofreader(model: model, makeNonce: { "0badc0de" }).proofread("Hi")
    #expect(seen.value == PromptBuilder.proofread("Hi", nonce: "0badc0de"))
  }
}

/// The last request a stub model received.
private final class SeenRequest: Sendable {
  private let request = Mutex<ModelRequest?>(nil)
  var value: ModelRequest? { request.withLock { $0 } }
  func set(_ value: ModelRequest) { request.withLock { $0 = value } }
}
