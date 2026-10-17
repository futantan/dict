// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The History page's type filter (Design/main-app/history.html): 全部, 单词, 翻译, 纠错, 译成外语.
public enum HistoryKind: String, Sendable, CaseIterable {
  case all
  /// Lookups.
  case words
  /// Sentences translated into my language.
  case translations
  /// Corrections and rewrites: both come from the Write shortcut and show a diff.
  case corrections
  case translationsOut

  /// The sentence kinds shown; empty for none.
  var sentenceKinds: [SentenceKind] {
    switch self {
    case .all: SentenceKind.allCases
    case .words: []
    case .translations: [.translated]
    case .corrections: [.corrected, .improved]
    case .translationsOut: [.translatedOut]
    }
  }

  var showsLookups: Bool { self == .all || self == .words }
}

/// What the History page lists.
public struct HistoryFilter: Hashable, Sendable {
  public var kind: HistoryKind
  /// Matched anywhere in the lemma, the text as met, the sentence, the meaning and the
  /// translations; blank matches everything.
  public var search: String
  /// A bundle id; nil for every app.
  public var sourceApp: String?

  public init(kind: HistoryKind = .all, search: String = "", sourceApp: String? = nil) {
    self.kind = kind
    self.search = search
    self.sourceApp = sourceApp
  }
}

/// Where the next page of the history starts: right after this item, in the order of
/// `history(_:after:limit:)`.
public struct HistoryCursor: Hashable, Sendable {
  let seconds: Int64
  /// A lookup sorts before a sentence event of the same second.
  let rank: Int64
  let id: Int64

  public init(_ activity: Activity) {
    seconds = Int64(activity.date.timeIntervalSince1970.rounded(.down))
    switch activity {
    case .lookup(let lookup): (rank, id) = (1, lookup.encounter.id)
    case .sentence(let event): (rank, id) = (0, event.id)
    }
  }
}

/// One page of the history, and whether more follow.
public struct HistorySlice: Hashable, Sendable {
  public var items: [Activity]
  public var hasMore: Bool
}

/// 「共 214 条 · 本周 63 条」: lookups and sentence events in all, and since a day.
public struct HistoryCounts: Hashable, Sendable {
  public var total: Int
  public var since: Int

  public init(total: Int, since: Int) {
    self.total = total
    self.since = since
  }
}

/// The History page's queries and deletes.
extension VocabStore {
  /// Lookups and sentence events matching `filter`, newest first, `limit` at a time; a lookup
  /// comes before a sentence event of the same second. Pass the last item of a page as
  /// `after` for the next one.
  public func history(_ filter: HistoryFilter, after cursor: HistoryCursor?, limit: Int)
    throws -> HistorySlice
  {
    let needle = filter.search.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = VocabValue.text("%\(Self.escapeLike(needle))%")
    let app = filter.sourceApp.vocabValue
    let fetch = VocabValue.integer(Int64(limit + 1))
    // A row comes after the cursor when its (time, rank, id) is smaller.
    let after = cursor.map { [VocabValue.integer($0.seconds), .integer($0.rank), .integer($0.id)] }
    let afterLookup = after == nil ? "" : "AND (e.seen_at, 1, e.id) < (?4, ?5, ?6)"
    let afterSentence = after == nil ? "" : "AND (created_at, 0, id) < (?4, ?5, ?6)"

    var lookups: [Activity] = []
    if filter.kind.showsLookups {
      lookups = try db.rows(
        """
        SELECT \(termColumns), \(encounterColumns)
        FROM encounter e JOIN term t ON t.id = e.term_id
        WHERE (?1 IS NULL OR e.source_app = ?1)
          AND (?2 = '%%' OR t.lemma LIKE ?2 ESCAPE '\\' OR e.surface LIKE ?2 ESCAPE '\\'
               OR e.sentence LIKE ?2 ESCAPE '\\' OR e.sense LIKE ?2 ESCAPE '\\'
               OR e.sentence_translation LIKE ?2 ESCAPE '\\')
          \(afterLookup)
        ORDER BY e.seen_at DESC, e.id DESC LIMIT ?3
        """, [app, pattern, fetch] + (after ?? [])
      ).compactMap { row -> Activity? in
        guard let term = Self.term(row), let encounter = Self.encounter(row, at: termColumnCount)
        else { return nil }
        return .lookup(DailyLog.Lookup(term: term, encounter: encounter))
      }
    }

    var sentences: [Activity] = []
    let kinds = filter.kind.sentenceKinds
    if !kinds.isEmpty {
      let kindList = kinds.map { "'\($0.rawValue)'" }.joined(separator: ", ")
      sentences = try db.rows(
        """
        SELECT \(sentenceColumns) FROM sentence_event
        WHERE kind IN (\(kindList))
          AND (?1 IS NULL OR source_app = ?1)
          AND (?2 = '%%' OR source LIKE ?2 ESCAPE '\\' OR result LIKE ?2 ESCAPE '\\')
          \(afterSentence)
        ORDER BY created_at DESC, id DESC LIMIT ?3
        """, [app, pattern, fetch] + (after ?? [])
      ).compactMap(Self.sentenceEvent).map(Activity.sentence)
    }

    let merged = (lookups + sentences).sorted { HistoryCursor($0) > HistoryCursor($1) }
    return HistorySlice(items: Array(merged.prefix(limit)), hasMore: merged.count > limit)
  }

  /// The bundle ids of the apps anything was recorded in, the most used first.
  public func historySourceApps() throws -> [String] {
    try db.rows(
      """
      SELECT source_app FROM (
        SELECT source_app FROM encounter UNION ALL SELECT source_app FROM sentence_event)
      WHERE source_app IS NOT NULL
      GROUP BY source_app ORDER BY count(*) DESC, source_app
      """
    ).compactMap { $0.first?.string }
  }

  /// Every lookup and sentence event, and those on or after `day`.
  public func historyCounts(since day: LocalDay) throws -> HistoryCounts {
    let row = try db.rows(
      """
      SELECT (SELECT count(*) FROM encounter) + (SELECT count(*) FROM sentence_event),
             (SELECT count(*) FROM encounter WHERE day >= ?1)
               + (SELECT count(*) FROM sentence_event WHERE day >= ?1)
      """, [.text(day.description)]
    ).first
    return HistoryCounts(total: row?[0].int ?? 0, since: row?[1].int ?? 0)
  }

  /// Deletes one lookup. A 查过 term left without encounters goes too; a 要学 one stays with
  /// its review. A term that keeps encounters has its first and last seen times recomputed.
  public func deleteEncounter(_ id: Int64) throws {
    try db.transaction { () throws(VocabError) in
      guard
        let termID = try db.scalar("SELECT term_id FROM encounter WHERE id = ?", [.integer(id)])
          .int64
      else { return }
      try db.rows("DELETE FROM encounter WHERE id = ?", [.integer(id)])
      try db.rows(
        """
        DELETE FROM term WHERE id = ?1 AND tier = 'seen'
          AND NOT EXISTS (SELECT 1 FROM encounter e WHERE e.term_id = ?1)
        """, [.integer(termID)])
      try db.rows(
        """
        UPDATE term SET
          created_at   = (SELECT min(seen_at) FROM encounter e WHERE e.term_id = ?1),
          last_seen_at = (SELECT max(seen_at) FROM encounter e WHERE e.term_id = ?1)
        WHERE id = ?1 AND EXISTS (SELECT 1 FROM encounter e WHERE e.term_id = ?1)
        """, [.integer(termID)])
    }
  }

  /// Deletes one sentence translation, correction or rewrite.
  public func deleteSentenceEvent(_ id: Int64) throws {
    try db.rows("DELETE FROM sentence_event WHERE id = ?", [.integer(id)])
  }
}

extension HistoryCursor: Comparable {
  public static func < (a: HistoryCursor, b: HistoryCursor) -> Bool {
    (a.seconds, a.rank, a.id) < (b.seconds, b.rank, b.id)
  }
}
