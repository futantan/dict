// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Synchronization
import Testing

@testable import DictCore

private let completed = StreamEvent.finished(.complete, nil)

/// The requests a stub model received.
private final class Requests: Sendable {
  let list = Mutex<[ModelRequest]>([])
}

private func maker(_ reply: StubModel.Reply, requests: Requests? = nil) -> CardMaker {
  CardMaker(
    model: StubModel { request in
      requests?.list.withLock { $0.append(request) }
      return reply
    }, makeNonce: { "0badc0de" })
}

/// Every event of one card stream, then the error's description or "end".
private func events(_ reply: StubModel.Reply) async -> [String] {
  var seen: [String] = []
  do {
    for try await event in maker(reply).card(
      term: "ran", context: "She ran a bakery.", pair: LanguagePair(), accent: .american)
    {
      switch event {
      case .fields(let definition, let translation):
        seen.append("fields \(definition ?? "-") \(translation ?? "-")")
      case .notATerm: seen.append("notATerm")
      case .card(let card): seen.append("card \(card.definition)")
      }
    }
    seen.append("end")
  } catch {
    seen.append("error: \(error)")
  }
  return seen
}

/// `json` cut into deltas of `size` characters.
private func deltas(_ json: String, size: Int) -> [StreamEvent] {
  var events: [StreamEvent] = []
  var rest = Substring(json)
  while !rest.isEmpty {
    events.append(.text(String(rest.prefix(size))))
    rest = rest.dropFirst(size)
  }
  return events
}

struct CardMakerTests {
  @Test func asksWithTheCardPrompt() async throws {
    let requests = Requests()
    let stream = maker(.events([.text(cardJSON()), completed]), requests: requests).card(
      term: "ran", context: "She ran a bakery.", pair: LanguagePair(), accent: .british)
    for try await _ in stream {}
    let expected = PromptBuilder.card(
      term: "ran", context: "She ran a bakery.", pair: LanguagePair(), accent: .british,
      nonce: "0badc0de")
    #expect(requests.list.withLock { $0 } == [expected])
  }

  @Test func theShortFieldsComeFirstThenTheWholeCard() async {
    let seen = await events(.events(deltas(cardJSON(), size: 7) + [completed]))
    #expect(seen == ["fields 经营 -", "fields 经营 她经营一家面包店。", "card 经营", "end"])
  }

  @Test func notATermEndsTheStreamEarly() async {
    let json = cardJSON(status: "not_a_term")
    #expect(await events(.events(deltas(json, size: 5) + [completed])) == ["notATerm", "end"])
  }

  @Test func discardedTextStartsTheScanOver() async {
    let seen = await events(
      .events([
        .text(#"{"status":"ok","definition":"wrong","#), .discardText, .text(cardJSON()),
        completed,
      ]))
    #expect(
      seen == ["fields wrong -", "fields 经营 她经营一家面包店。", "card 经营", "end"])
  }

  @Test func onlyACompleteAnswerBecomesACard() async {
    let json = StreamEvent.text(cardJSON())
    #expect(await events(.events([json, .finished(.truncated, nil)])).last == "error: truncated")
    #expect(await events(.events([json, .finished(.refused, nil)])).last == "error: refused")
    #expect(await events(.events([json])).last == "error: interrupted")
    #expect(await events(.events([.text("{}"), completed])) == ["error: malformed"])
  }

  @Test func modelErrorsPassThrough() async {
    #expect(await events(.failure(.unauthorized)) == ["error: unauthorized"])
  }
}
