// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// A due word as the review page shows it: the scheduler's item, what the log adds and the
/// stored card.
struct ReviewCard: Equatable, Identifiable {
  let item: ReviewItem
  let history: ReviewHistory
  /// The term's latest card, for the part of speech, the sense and the phonetic.
  let card: WordCard?

  init(item: ReviewItem, history: ReviewHistory = ReviewHistory()) {
    self.item = item
    self.history = history
    card = item.term.card.flatMap { try? decodeCard($0.json) }
  }

  var id: Int64 { item.term.id }
  var lemma: String { item.term.lemma }
  /// The sentence the card asks with: the latest encounter that has one.
  var encounter: Encounter? { item.encounter }
  /// The encounter's sentence with the word as a gap; nil, so the front is the lemma, when
  /// there is no sentence or the word cannot be found in it.
  var cloze: Cloze? { encounter.flatMap(Cloze.init) }
  /// The meaning in that sentence, else the card's.
  var sense: String? {
    [encounter?.sense, card?.definition].compactMap(\.self).first { !$0.isEmpty }
  }
  var partOfSpeech: String? { card.flatMap { $0.partOfSpeech.isEmpty ? nil : $0.partOfSpeech } }
  var phonetic: String? { card.flatMap { $0.phonetic.isEmpty ? nil : $0.phonetic } }
}

/// A sentence split around the word it asks for.
struct Cloze: Equatable {
  let before: String
  let term: String
  let after: String
}

extension Cloze {
  /// The encounter's sentence around its recorded range, else around the first match of the
  /// word as it appeared; nil without a sentence or a match.
  init?(_ encounter: Encounter) {
    guard let sentence = encounter.sentence else { return nil }
    let units = sentence.utf16
    var range: Range<String.Index>?
    if let start = encounter.termStart, let length = encounter.termLength, start >= 0,
      length > 0, start + length <= units.count
    {
      let lower = units.index(units.startIndex, offsetBy: start)
      range = lower..<units.index(lower, offsetBy: length)
    } else if !encounter.surface.isEmpty {
      range = sentence.range(of: encounter.surface, options: [.caseInsensitive])
    }
    guard let range else { return nil }
    before = String(sentence[..<range.lowerBound])
    term = String(sentence[range])
    after = String(sentence[range.upperBound...])
  }
}

/// One review session of the page (Design/main-app/review.html): the due words in order,
/// where the user is, and how each word went. A pure value; `ReviewModel` records the
/// ratings `answer` hands back.
///
/// Only a word's first rating counts and is recorded. 忘了 puts the word back at the end of
/// the session once; that second showing is practice, so the scheduler keeps the 忘了.
struct ReviewSession: Equatable {
  private(set) var queue: [ReviewCard]
  private(set) var position = 0
  private(set) var isRevealed = false
  /// Each word's first rating.
  private(set) var results: [Int64: Rating] = [:]
  /// The different words of the session: the N of 「n / N」.
  let total: Int

  /// `cards` in order, each word once.
  init(cards: [ReviewCard]) {
    var seen = Set<Int64>()
    queue = cards.filter { seen.insert($0.id).inserted }
    total = queue.count
  }

  var current: ReviewCard? { queue.indices.contains(position) ? queue[position] : nil }
  var isFinished: Bool { current == nil }
  /// Words rated at least once: the n of 「n / N」 and 「今天已复习」.
  var reviewed: Int { results.count }
  var remembered: Int { results.values.count { $0 == .good } }
  var forgotten: Int { results.values.count { $0 == .again } }
  /// Whether the current card is the second showing of a forgotten word.
  var isRepeat: Bool { current.map { results[$0.id] != nil } ?? false }

  mutating func reveal() {
    if current != nil { isRevealed = true }
  }

  /// Rates the revealed current card and moves to the next one. Returns the card when this is
  /// its word's first rating, which is the one to record; nil for a repeat or when the card
  /// is not revealed yet.
  mutating func answer(_ rating: Rating) -> ReviewCard? {
    guard isRevealed, let card = current else { return nil }
    let isFirst = results[card.id] == nil
    if isFirst {
      results[card.id] = rating
      if rating == .again { queue.append(card) }
    }
    position += 1
    isRevealed = false
    return isFirst ? card : nil
  }
}
