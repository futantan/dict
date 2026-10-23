// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The counts of one day on the main window's Today page (Design/main-app/README.md).
public struct DayCounts: Hashable, Sendable {
  /// Different terms looked up.
  public var terms = 0
  /// Every lookup, a term looked up twice counting twice.
  public var lookups = 0
  /// Sentences translated into my language.
  public var translations = 0
  /// Corrections, rewrites and translations out of my language.
  public var writes = 0
  /// The writes whose result replaced the text in the other app.
  public var replaced = 0

  public init(
    terms: Int = 0, lookups: Int = 0, translations: Int = 0, writes: Int = 0, replaced: Int = 0
  ) {
    self.terms = terms
    self.lookups = lookups
    self.translations = translations
    self.writes = writes
    self.replaced = replaced
  }
}

/// One line of the window's recent activity: a lookup or a sentence event.
public enum Activity: Hashable, Sendable {
  case lookup(DailyLog.Lookup)
  case sentence(SentenceEvent)

  public var date: Date {
    switch self {
    case .lookup(let lookup): lookup.encounter.seenAt
    case .sentence(let event): event.createdAt
    }
  }
}

/// Everything the log holds, for the privacy note in Settings.
public struct VocabTotals: Hashable, Sendable {
  public var terms: Int
  public var sentences: Int

  public init(terms: Int, sentences: Int) {
    self.terms = terms
    self.sentences = sentences
  }
}

/// The read-side queries of the main window. Each page adds the queries it needs here, next
/// to these, so the window never writes SQL of its own.
extension VocabStore {
  public func dayCounts(on day: LocalDay) throws -> DayCounts {
    let text = VocabValue.text(day.description)
    let lookups = try db.rows(
      "SELECT count(DISTINCT term_id), count(*) FROM encounter WHERE day = ?", [text]
    ).first
    let sentences = try db.rows(
      """
      SELECT count(*) FILTER (WHERE kind = 'translated'),
             count(*) FILTER (WHERE kind <> 'translated'),
             count(*) FILTER (WHERE kind <> 'translated' AND applied <> 0)
      FROM sentence_event WHERE day = ?
      """, [text]
    ).first
    return DayCounts(
      terms: lookups?[0].int ?? 0, lookups: lookups?[1].int ?? 0,
      translations: sentences?[0].int ?? 0, writes: sentences?[1].int ?? 0,
      replaced: sentences?[2].int ?? 0)
  }

  /// The latest lookups and sentence events of any day, newest first.
  public func recentActivity(limit: Int) throws -> [Activity] {
    let limit = VocabValue.integer(Int64(limit))
    let lookups = try db.rows(
      """
      SELECT \(termColumns), \(encounterColumns)
      FROM encounter e JOIN term t ON t.id = e.term_id
      ORDER BY e.seen_at DESC, e.id DESC LIMIT ?
      """, [limit]
    ).compactMap { row -> Activity? in
      guard let term = Self.term(row), let encounter = Self.encounter(row, at: termColumnCount)
      else { return nil }
      return .lookup(DailyLog.Lookup(term: term, encounter: encounter))
    }
    let sentences = try db.rows(
      "SELECT \(sentenceColumns) FROM sentence_event ORDER BY created_at DESC, id DESC LIMIT ?",
      [limit]
    ).compactMap(Self.sentenceEvent).map(Activity.sentence)
    // Stable, so a lookup and an event of the same second keep a fixed order.
    let merged = (lookups + sentences).enumerated().sorted {
      $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset < $1.offset
    }
    return merged.prefix(Int(limit.int ?? 0)).map(\.element)
  }

  /// 查过 terms met at least `minEncounters` times, the most met first: 「反复遇到，还没标要学」.
  public func frequentNotLearning(minEncounters: Int, limit: Int) throws -> [TermSummary] {
    try db.rows(
      """
      SELECT \(termColumns) FROM term t
      WHERE t.tier = 'seen'
        AND (SELECT count(*) FROM encounter c WHERE c.term_id = t.id) >= ?
      ORDER BY 6 DESC, t.last_seen_at DESC, t.id DESC LIMIT ?
      """, [.integer(Int64(minEncounters)), .integer(Int64(limit))]
    ).compactMap { Self.term($0) }
  }

  /// How many 要学 terms are due on or before `day`; `dueReviews` lists them.
  public func dueCount(on day: LocalDay) throws -> Int {
    try db.scalar(
      """
      SELECT count(*) FROM review_state r JOIN term t ON t.id = r.term_id
      WHERE t.tier = 'learning' AND r.due_day <= ?
      """, [.text(day.description)]
    ).int ?? 0
  }

  /// How many terms are 要学.
  public func learningCount() throws -> Int {
    try db.scalar("SELECT count(*) FROM term WHERE tier = 'learning'").int ?? 0
  }

  public func totals() throws -> VocabTotals {
    VocabTotals(
      terms: try db.scalar("SELECT count(*) FROM term").int ?? 0,
      sentences: try db.scalar("SELECT count(*) FROM sentence_event").int ?? 0)
  }

  /// Deletes every term, encounter, sentence event and review, for 「清除所有记录」. The file
  /// and its schema stay.
  public func deleteAll() throws {
    try db.transaction { () throws(VocabError) in
      // Terms cascade to their encounters, review state and review log.
      try db.execute("DELETE FROM term; DELETE FROM sentence_event;")
    }
  }
}
