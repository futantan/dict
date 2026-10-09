// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The model's dictionary card for a selected term (architecture 6.6). Every field is
/// required by the strict schema; "" and empty arrays mean unknown or none.
public struct WordCard: Codable, Sendable, Equatable {
  public enum Status: String, Codable, Sendable { case ok, notATerm = "not_a_term" }

  public struct Sense: Codable, Sendable, Equatable {
    public var partOfSpeech: String
    public var definition: String

    public init(partOfSpeech: String, definition: String) {
      self.partOfSpeech = partOfSpeech
      self.definition = definition
    }
  }

  public struct Example: Codable, Sendable, Equatable {
    public var sentence: String
    public var translation: String

    public init(sentence: String, translation: String) {
      self.sentence = sentence
      self.translation = translation
    }
  }

  public struct Collocation: Codable, Sendable, Equatable {
    public var phrase: String
    public var meaning: String

    public init(phrase: String, meaning: String) {
      self.phrase = phrase
      self.meaning = meaning
    }
  }

  public var status: Status
  public var lemma: String
  /// Shown only when the dictionary layer has no pronunciation.
  public var phonetic: String
  /// One of `partsOfSpeech`.
  public var partOfSpeech: String
  /// The meaning in the context sentence, in the user's own language.
  public var definition: String
  /// The context sentence in the user's own language; "" without a context.
  public var contextTranslation: String
  /// At most `maxOtherSenses`.
  public var otherSenses: [Sense]
  /// One or two for a term, never the context sentence; none for `notATerm`.
  public var examples: [Example]
  /// At most `maxCollocations`.
  public var collocations: [Collocation]
  /// A CEFR level or "". Never shown: it varies by a level between calls.
  public var level: String

  public init(
    status: Status, lemma: String, phonetic: String, partOfSpeech: String, definition: String,
    contextTranslation: String, otherSenses: [Sense], examples: [Example],
    collocations: [Collocation], level: String
  ) {
    self.status = status
    self.lemma = lemma
    self.phonetic = phonetic
    self.partOfSpeech = partOfSpeech
    self.definition = definition
    self.contextTranslation = contextTranslation
    self.otherSenses = otherSenses
    self.examples = examples
    self.collocations = collocations
    self.level = level
  }

  /// The fields in the order the schema declares them, and so the order a strict model
  /// writes them: `status` first, the short strings, then the arrays.
  public static let keys = [
    "status", "lemma", "phonetic", "partOfSpeech", "definition", "contextTranslation",
    "otherSenses", "examples", "collocations", "level",
  ]
  public static let partsOfSpeech = [
    "noun", "verb", "adjective", "adverb", "preposition", "conjunction", "pronoun", "determiner",
    "interjection", "phrasal verb", "idiom", "phrase", "abbreviation", "",
  ]
  public static let levels = ["A1", "A2", "B1", "B2", "C1", "C2", ""]
  public static let maxOtherSenses = 3
  public static let maxExamples = 2
  public static let maxCollocations = 3
}

/// Why a card answer is unusable.
public enum CardError: Error, Sendable, Equatable {
  /// Not the card the schema describes: invalid JSON, a missing field, a value outside its
  /// enum or an array over its limit.
  case malformed
}

/// Decodes the model's card answer and checks what the strict schema promises, so a provider
/// without strict mode cannot put a malformed card on screen.
public func decodeCard(_ json: String) throws(CardError) -> WordCard {
  let card: WordCard
  do {
    card = try JSONDecoder().decode(WordCard.self, from: Data(json.utf8))
  } catch {
    throw .malformed
  }
  let partsOfSpeech = [card.partOfSpeech] + card.otherSenses.map(\.partOfSpeech)
  guard partsOfSpeech.allSatisfy(WordCard.partsOfSpeech.contains),
    WordCard.levels.contains(card.level),
    card.otherSenses.count <= WordCard.maxOtherSenses,
    card.examples.count <= WordCard.maxExamples,
    card.collocations.count <= WordCard.maxCollocations
  else { throw .malformed }
  return card
}
