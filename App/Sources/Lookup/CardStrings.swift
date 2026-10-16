// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// The word card's wording and action ids (table `Card`).
enum CardStrings {
  /// Action ids reported through `PanelController.onAction`; ⌘S and ⌘P send the first two.
  static let learnAction = "card.learn"
  static let pronounceAction = "card.pronounce"
  static let translateAction = "card.translate"
  /// 「查这个词」 on a translation.
  static let lookUpAction = "translation.lookUp"

  static let learn = String(
    localized: "Learn", table: "Card", comment: "Card action: mark the word as one to learn")

  static let learning = String(
    localized: "Learning", table: "Card",
    comment: "Card action when the word is already marked to learn; pressing it unmarks it")

  static let pronounce = String(
    localized: "Pronounce", table: "Card", comment: "Card action: say the word")

  static let translateAsSentence = String(
    localized: "Translate", table: "Card",
    comment: "Card action: translate the selection instead of looking it up")

  static let lookUp = String(
    localized: "Look Up", table: "Card",
    comment: "Action under a translation: look the selection up as a word instead")

  static let inThisSentence = String(
    localized: "In this sentence", table: "Card",
    comment: "Card heading over the meaning the word has in the sentence it was read in")

  static let otherSenses = String(
    localized: "Other meanings", table: "Card", comment: "Card heading over other senses")

  static let examples = String(
    localized: "Examples", table: "Card", comment: "Card heading over example sentences")

  static let collocations = String(
    localized: "Collocations", table: "Card",
    comment: "Card heading over common word combinations")

  static let lookingUp = String(
    localized: "Looking up…", table: "Card",
    comment: "Shown on the card while the model's explanation is on its way")

  /// 「第 N 次」.
  static func encounters(_ count: Int) -> String {
    String(
      format: String(
        localized: "Looked up %lld times", table: "Card",
        comment: "On the card: how many times this word has been looked up, this time included"),
      count)
  }

  static func band(_ band: FrequencyBand) -> String {
    switch band {
    case .common:
      String(localized: "Common", table: "Card", comment: "Word frequency band")
    case .moderate:
      String(localized: "Less common", table: "Card", comment: "Word frequency band")
    case .rare:
      String(localized: "Rare", table: "Card", comment: "Word frequency band")
    }
  }

  /// The short English label of a part of speech, as learner's dictionaries print it in
  /// every UI language (n., v., adj.).
  static func partOfSpeech(_ name: String) -> String {
    switch name {
    case "noun": "n."
    case "verb": "v."
    case "adjective": "adj."
    case "adverb": "adv."
    case "preposition": "prep."
    case "conjunction": "conj."
    case "pronoun": "pron."
    case "determiner": "det."
    case "interjection": "interj."
    case "phrasal verb": "phr. v."
    case "abbreviation": "abbr."
    case "phrase": "phr."
    default: name
    }
  }

  /// The selection has no word in it (architecture 5.1).
  static let nothingToLookUp = PanelNotice(
    symbol: "circle.slash",
    title: String(
      localized: "Nothing to look up", table: "Card",
      comment: "Title when the selection is a number, a link or symbols"),
    message: String(
      localized:
        "The selection is a number, a link or symbols, with no word to look up or translate.",
      table: "Card", comment: "Why nothing was looked up"),
    kind: .information)

  /// Under a card with no model to explain the word in its sentence.
  static let needsModelNote = PanelNote(
    String(
      localized: "Set up a model to see what the word means in this sentence.", table: "Card",
      comment: "Under a dictionary-only card when no model is set up"),
    action: PanelAction(
      id: TranslationStrings.openSettingsAction,
      title: String(
        localized: "Open Settings", table: "Translation", comment: "Button that opens Settings")))

  /// Under a card whose model part failed; the dictionary part stays.
  static func failureNote(_ error: any Error) -> PanelNote {
    PanelNote(
      String(
        format: String(
          localized: "The model couldn’t explain this word (%@).", table: "Card",
          comment: "Under a card whose model explanation failed; %@ is the reason"),
        TranslationStrings.modelFailureReason(error)),
      action: TranslationStrings.isKeyProblem(error)
        ? needsModelNote.action
        : PanelAction(
          id: TranslationStrings.retryAction,
          title: String(localized: "Try Again", table: "Translation", comment: "Retry button")))
  }
}
