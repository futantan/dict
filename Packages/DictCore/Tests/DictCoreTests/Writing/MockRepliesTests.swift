// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

/// `Fixtures/MockModel/replies.json`, the reply table of `scripts/fake-model.py`.
private func mockReplies() throws -> [String: Any] {
  let root = URL(fileURLWithPath: #filePath)
  let url = (0..<6).reduce(root) { url, _ in url.deletingLastPathComponent() }
    .appending(path: "Fixtures/MockModel/replies.json")
  let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
  return try #require(object as? [String: Any])
}

/// Every proofreading reply of the mock model decodes and applies to the text it answers,
/// so the mock never shows an error the real decoder would not.
struct MockRepliesTests {
  @Test func everyProofreadingReplyAppliesToItsText() throws {
    let proofreads = try #require(try mockReplies()["proofreads"] as? [String: Any])
    #expect(!proofreads.isEmpty)
    for (source, reply) in proofreads {
      let json = try #require(
        String(data: try JSONSerialization.data(withJSONObject: reply), encoding: .utf8))
      let edits = try decodeEdits(json)
      let applied = try applyEdits(edits, to: source).get()
      #expect(applied.changeCount == edits.count, "\(source)")
    }
  }

  @Test func theAcceptanceSentenceShowsTwoChanges() throws {
    let proofreads = try #require(try mockReplies()["proofreads"] as? [String: Any])
    let source = "Their going to the park tomorow, I think it will be fun."
    let reply = try #require(proofreads[source])
    let json = try #require(
      String(data: try JSONSerialization.data(withJSONObject: reply), encoding: .utf8))
    let applied = try applyEdits(try decodeEdits(json), to: source).get()
    #expect(applied.text == "They're going to the park tomorrow. I think it will be fun.")
    #expect(applied.changeCount == 2)
  }

  /// Every card of the table, and the fallback with a term filled in, decodes with the real
  /// decoder; a term's card has examples, and a context sentence has its translation.
  @Test func everyCardReplyDecodes() throws {
    let replies = try mockReplies()
    let cards = try #require(replies["cards"] as? [String: [String: Any]])
    #expect(cards.count >= 4)
    for (term, entry) in cards {
      let context = try #require(entry["context"] as? String, "\(term)")
      let data = try JSONSerialization.data(withJSONObject: entry["card"] ?? [:])
      let card = try decodeCard(try #require(String(data: data, encoding: .utf8)))
      if card.status == .ok {
        #expect(!card.definition.isEmpty, "\(term)")
        #expect((1...2).contains(card.examples.count), "\(term)")
        #expect(card.contextTranslation.isEmpty == context.isEmpty, "\(term)")
      }
    }
    #expect(try decodeCard(try fallbackCard(replies)).lemma == "{term}")
  }

  @Test func theTableCoversAnInflectedFormAndANonTerm() throws {
    let cards = try #require(try mockReplies()["cards"] as? [String: [String: Any]])
    func card(_ term: String) throws -> WordCard {
      let entry = try #require(cards[term]?["card"])
      return try decodeCard(
        try #require(
          String(data: try JSONSerialization.data(withJSONObject: entry), encoding: .utf8)))
    }
    #expect(try card("ran").lemma == "run")
    #expect(try card("fine").partOfSpeech == "noun")
    #expect(try card("asdfgh").status == .notATerm)
  }

  private func fallbackCard(_ replies: [String: Any]) throws -> String {
    let fallback = try #require(replies["cardFallback"])
    return try #require(
      String(data: try JSONSerialization.data(withJSONObject: fallback), encoding: .utf8))
  }

  @Test func everyTranslationReplyIsText() throws {
    let translations = try #require(try mockReplies()["translations"] as? [String: String])
    #expect(!translations.isEmpty)
    #expect(translations.values.allSatisfy { !$0.isEmpty })
  }
}
