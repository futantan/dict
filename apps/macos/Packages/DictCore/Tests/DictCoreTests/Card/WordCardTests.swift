// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

/// A complete card answer as the schema asks for it, with fields that tests can override.
func cardJSON(
  status: String = "ok", partOfSpeech: String = "verb", level: String = "A2",
  otherSenses: Int = 1, examples: Int = 1, collocations: Int = 1
) -> String {
  let sense = #"{"partOfSpeech":"verb","definition":"跑"}"#
  let example = #"{"sentence":"He runs a shop.","translation":"他开了一家店。"}"#
  let collocation = #"{"phrase":"run a business","meaning":"经营生意"}"#
  func list(_ item: String, _ count: Int) -> String {
    "[" + Array(repeating: item, count: count).joined(separator: ",") + "]"
  }
  return """
    {"status":"\(status)","lemma":"run","phonetic":"/rʌn/","partOfSpeech":"\(partOfSpeech)",\
    "definition":"经营","contextTranslation":"她经营一家面包店。",\
    "otherSenses":\(list(sense, otherSenses)),"examples":\(list(example, examples)),\
    "collocations":\(list(collocation, collocations)),"level":"\(level)"}
    """
}

struct DecodeCardTests {
  @Test func decodesEveryField() throws {
    let card = try decodeCard(cardJSON())
    #expect(
      card
        == WordCard(
          status: .ok, lemma: "run", phonetic: "/rʌn/", partOfSpeech: "verb", definition: "经营",
          contextTranslation: "她经营一家面包店。",
          otherSenses: [WordCard.Sense(partOfSpeech: "verb", definition: "跑")],
          examples: [WordCard.Example(sentence: "He runs a shop.", translation: "他开了一家店。")],
          collocations: [WordCard.Collocation(phrase: "run a business", meaning: "经营生意")],
          level: "A2"))
  }

  @Test func decodesNotATermWithEmptyFields() throws {
    let json = """
      {"status":"not_a_term","lemma":"","phonetic":"","partOfSpeech":"","definition":"",\
      "contextTranslation":"","otherSenses":[],"examples":[],"collocations":[],"level":""}
      """
    let card = try decodeCard(json)
    #expect(card.status == .notATerm)
    #expect(card.examples.isEmpty)
  }

  @Test func rejectsWhatTheSchemaRulesOut() {
    let broken = [
      "", "{", #"{"status":"ok"}"#, cardJSON(status: "maybe"), cardJSON(partOfSpeech: "verbs"),
      cardJSON(level: "D1"), cardJSON(otherSenses: 4), cardJSON(examples: 3),
      cardJSON(collocations: 4),
      cardJSON().replacingOccurrences(
        of: #"[{"partOfSpeech":"verb","definition":"跑"}]"#,
        with: #"[{"partOfSpeech":"thing","definition":"跑"}]"#),
    ]
    for json in broken {
      #expect(throws: CardError.malformed, "\(json)") { try decodeCard(json) }
    }
  }

  @Test func acceptsTheLimitsAndEmptyEnums() throws {
    let card = try decodeCard(
      cardJSON(partOfSpeech: "", level: "", otherSenses: 3, examples: 2, collocations: 3))
    #expect(card.otherSenses.count == 3)
    #expect(card.examples.count == 2)
    #expect(card.collocations.count == 3)
  }

  @Test func enumListsMatchTheDocument() {
    #expect(
      WordCard.partsOfSpeech == [
        "noun", "verb", "adjective", "adverb", "preposition", "conjunction", "pronoun",
        "determiner", "interjection", "phrasal verb", "idiom", "phrase", "abbreviation", "",
      ])
    #expect(WordCard.levels == ["A1", "A2", "B1", "B2", "C1", "C2", ""])
  }
}
