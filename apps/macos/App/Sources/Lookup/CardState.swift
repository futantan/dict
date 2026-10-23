// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// What the word card shows (architecture 6.6): the dictionary layer at once, then the
/// model's card as it streams in. Built by the session coordinator through the pure
/// functions below; the view only draws it.
struct CardState: Sendable, Equatable {
  /// One dictionary sense: a part of speech as stored (`verb`) and a short gloss.
  struct Sense: Sendable, Equatable {
    var partOfSpeech: String
    var gloss: String
  }

  /// The dictionary's American or British transcription.
  enum Transcription: Sendable, Equatable {
    case us, uk
  }

  enum Model: Sendable, Equatable {
    /// The card has been asked for; `definition` and `contextTranslation` may arrive first.
    case loading
    /// The whole card arrived and is shown.
    case complete
    /// No model card: none is set up, or it failed. The panel's note says which.
    case unavailable
  }

  /// How many dictionary senses the card shows; the database keeps them all (architecture
  /// 7.2).
  static let shownSenses = 3

  /// The text as selected, trimmed.
  var term: String
  /// The dictionary form shown as the title: the dictionary's, else the model's, else `term`.
  var lemma: String
  /// From the dictionary in the chosen accent; the model's only when the dictionary has none.
  var phonetic: String?
  /// Which of the dictionary's transcriptions `phonetic` is; nil for the model's.
  var transcription: Transcription?
  var senses: [Sense]
  /// nil without a dictionary entry.
  var band: FrequencyBand?
  /// The sentence the term was read in.
  var context: String?
  /// The meaning in this sentence, from the model.
  var definition: String?
  /// The model's part of speech for `definition`; it comes with the whole card.
  var partOfSpeech: String?
  var contextTranslation: String?
  var otherSenses: [WordCard.Sense] = []
  var examples: [WordCard.Example] = []
  /// Empty for rare words, whose collocations the model tends to invent (architecture 6.6).
  var collocations: [WordCard.Collocation] = []
  var model: Model
  /// 「第 N 次」: how many times the term has been looked up, this time included; nil until
  /// the lookup is recorded.
  var encounters: Int?
  /// The term is marked 要学.
  var isLearning = false

  /// The card before the model answers.
  init(
    term: String, context: String?, entry: LexiconEntry?, accent: Accent, model: Model
  ) {
    self.term = term
    self.context = context
    lemma = entry?.lemma ?? term
    let pronunciation = entry.flatMap { Self.pronunciation($0, accent: accent) }
    phonetic = pronunciation?.ipa
    transcription = pronunciation?.transcription
    senses = (entry?.senses ?? []).prefix(Self.shownSenses).map {
      Sense(partOfSpeech: $0.pos, gloss: $0.gloss)
    }
    band = entry?.band
    self.model = model
  }

  /// The dictionary has an entry for the term.
  var hasDictionary: Bool { band != nil }

  /// The card's count line shows from the second lookup on.
  var shownEncounters: Int? {
    encounters.flatMap { $0 > 1 ? $0 : nil }
  }

  /// The senses under the title: the dictionary's, else the model's definition, which is
  /// then the card's main meaning rather than a meaning "in this sentence".
  var mainSenses: [Sense] {
    if !senses.isEmpty { return senses }
    return definition.map { [Sense(partOfSpeech: partOfSpeech ?? "", gloss: $0)] } ?? []
  }

  /// The meaning the "In this sentence" section leads with; nil when it is already the main
  /// meaning.
  var sentenceMeaning: String? {
    senses.isEmpty ? nil : definition
  }

  /// With the dictionary, the section waits for the model's meaning; without it, it holds
  /// only the sentence and its translation, and a typed term has neither.
  var showsSentenceSection: Bool {
    senses.isEmpty
      ? context != nil || contextTranslation != nil
      : model == .loading || definition != nil
  }

  /// What ⌘C copies when nothing is selected: the title and the meaning shown first.
  var copyableText: String {
    let meaning = definition ?? senses.first?.gloss
    return [lemma, meaning].compactMap(\.self).joined(separator: "\n")
  }

  /// The short fields of a streaming card.
  mutating func show(definition: String?, contextTranslation: String?) {
    if let definition, !definition.isEmpty { self.definition = definition }
    if let contextTranslation, !contextTranslation.isEmpty {
      self.contextTranslation = contextTranslation
    }
  }

  /// The complete card. The pronunciation and title stay the dictionary's when it has them,
  /// and the model's level is never shown (architecture 6.6).
  mutating func show(_ card: WordCard) {
    show(definition: card.definition, contextTranslation: card.contextTranslation)
    if !hasDictionary, !card.lemma.isEmpty { lemma = card.lemma }
    if phonetic == nil, !card.phonetic.isEmpty { phonetic = card.phonetic }
    if !card.partOfSpeech.isEmpty { partOfSpeech = card.partOfSpeech }
    otherSenses = card.otherSenses
    examples = card.examples
    collocations = band == .rare ? [] : card.collocations
    model = .complete
  }

  /// The IPA for the accent: American and Canadian English read the US transcription,
  /// the others the UK one; either stands in for the other when missing.
  static func phonetic(_ entry: LexiconEntry, accent: Accent) -> String? {
    pronunciation(entry, accent: accent)?.ipa
  }

  /// `phonetic` and which transcription it is.
  private static func pronunciation(_ entry: LexiconEntry, accent: Accent) -> (
    ipa: String, transcription: Transcription
  )? {
    let us = entry.ipaUS.flatMap { $0.isEmpty ? nil : (ipa: $0, transcription: Transcription.us) }
    let uk = entry.ipaUK.flatMap { $0.isEmpty ? nil : (ipa: $0, transcription: Transcription.uk) }
    switch accent {
    case .american, .canadian: return us ?? uk
    case .british, .australian, .indian: return uk ?? us
    }
  }
}
