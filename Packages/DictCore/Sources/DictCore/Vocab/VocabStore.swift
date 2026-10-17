// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation
import SQLite3

/// The vocabulary log of architecture chapter 8: one sqlite file, one connection.
///
/// Every day comes from the caller as a `LocalDay` and every instant as a `Date`; the store
/// never reads the clock or a time zone, so its behaviour is a function of its inputs.
public actor VocabStore {
  /// The `PRAGMA user_version` this build writes.
  public static let schemaVersion = migrations.count

  /// Internal so the read-side queries of the app's windows (`VocabStore+Window.swift`) can
  /// live in files of their own.
  let db: VocabDatabase
  private let autoPromotion: AutoPromotion?

  /// Opens or creates the file at `url`, turns on foreign keys and WAL, and migrates it. A file
  /// that is not a readable sqlite database is renamed `<name>.bad-<UTC time>` and replaced by
  /// a new one; a file from a newer schema throws `VocabError.newerSchema` and is left alone.
  /// `autoPromotion` nil turns automatic promotion to 要学 off.
  public init(url: URL, autoPromotion: AutoPromotion? = .standard) throws {
    db = try Self.open(url)
    self.autoPromotion = autoPromotion
  }

  // MARK: Recording

  /// Records one lookup and returns the term with the count including it. The term is keyed by
  /// `normalizedKey(lookup.lemma)`; the first lemma seen keeps being its display form.
  public func recordLookup(_ lookup: LookupRecord) throws -> TermSummary {
    let key = normalizedKey(lookup.lemma)
    guard !key.isEmpty else { throw VocabError.emptyLemma }
    return try db.transaction { () throws(VocabError) -> TermSummary in
      let seenAt = VocabValue.integer(Self.seconds(lookup.seenAt))
      let termID = try db.scalar(
        """
        INSERT INTO term (language, lemma, lemma_key, card_json, card_version, created_at,
                          last_seen_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (language, lemma_key) DO UPDATE SET
          last_seen_at = max(last_seen_at, excluded.last_seen_at),
          card_json    = coalesce(excluded.card_json, card_json),
          card_version = iif(excluded.card_json IS NULL, card_version, excluded.card_version)
        RETURNING id
        """,
        [
          .text(lookup.language), .text(lookup.lemma), .text(key),
          (lookup.card?.json).vocabValue, (lookup.card?.version).vocabValue,
          seenAt, seenAt,
        ]
      ).int64.orThrow()
      let encounterID = try db.scalar(
        """
        INSERT INTO encounter (term_id, kind, surface, sentence, term_start, term_length, sense,
                               sentence_translation, source_kind, source_app, source_url, day,
                               seen_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        RETURNING id
        """,
        [
          .integer(termID), .text(lookup.kind.rawValue), .text(lookup.surface),
          lookup.sentence.vocabValue, lookup.termStart.vocabValue, lookup.termLength.vocabValue,
          lookup.sense.vocabValue, lookup.sentenceTranslation.vocabValue,
          .text(lookup.source.rawValue), lookup.sourceApp.vocabValue,
          lookup.sourceURL.map(Self.withoutQuery).vocabValue, .text(lookup.day.description),
          seenAt,
        ]
      ).int64.orThrow()
      if let rule = autoPromotion, try reachesPromotion(termID, encounterID, rule) {
        try promote(termID, on: lookup.day)
      }
      return try summary(termID).orThrow()
    }
  }

  public func recordSentence(_ event: SentenceRecord) throws {
    try db.rows(
      """
      INSERT INTO sentence_event (kind, source, result, edits_json, applied, source_lang,
                                  result_lang, source_app, day, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        .text(event.kind.rawValue), .text(event.source), .text(event.result),
        event.editsJSON.vocabValue, .integer(event.applied ? 1 : 0), .text(event.sourceLanguage),
        .text(event.resultLanguage), event.sourceApp.vocabValue, .text(event.day.description),
        .integer(Self.seconds(event.createdAt)),
      ])
  }

  // MARK: Reading

  public func term(language: String, lemmaKey: String) throws -> TermSummary? {
    try db.rows(
      "SELECT \(termColumns) FROM term t WHERE t.language = ? AND t.lemma_key = ?",
      [.text(language), .text(lemmaKey)]
    ).first.flatMap { Self.term($0) }
  }

  /// The lookups and sentence events of `day`, each oldest first.
  public func day(_ day: LocalDay) throws -> DailyLog {
    let lookups = try db.rows(
      """
      SELECT \(termColumns), \(encounterColumns)
      FROM encounter e JOIN term t ON t.id = e.term_id
      WHERE e.day = ? ORDER BY e.seen_at, e.id
      """, [.text(day.description)]
    ).compactMap { row -> DailyLog.Lookup? in
      guard let term = Self.term(row), let encounter = Self.encounter(row, at: termColumnCount)
      else { return nil }
      return DailyLog.Lookup(term: term, encounter: encounter)
    }
    let sentences = try db.rows(
      """
      SELECT \(sentenceColumns) FROM sentence_event WHERE day = ? ORDER BY created_at, id
      """, [.text(day.description)]
    ).compactMap(Self.sentenceEvent)
    return DailyLog(day: day, lookups: lookups, sentences: sentences)
  }

  /// Terms with `prefix` in `lemma_key`, or in the sense of one of their encounters; lemma
  /// prefix matches first, then the most recently seen. `%` and `_` match themselves.
  public func search(_ query: String, limit: Int) throws -> [TermSummary] {
    let needle = Self.escapeLike(normalizedKey(query))
    guard !needle.isEmpty else { return [] }
    return try db.rows(
      """
      SELECT \(termColumns) FROM term t
      WHERE t.lemma_key LIKE ?1 ESCAPE '\\'
         OR EXISTS (SELECT 1 FROM encounter e
                    WHERE e.term_id = t.id AND e.sense LIKE ?1 ESCAPE '\\')
      ORDER BY t.lemma_key LIKE ?2 ESCAPE '\\' DESC, t.last_seen_at DESC, t.id DESC
      LIMIT ?3
      """, [.text("%\(needle)%"), .text("\(needle)%"), .integer(Int64(limit))]
    ).compactMap { Self.term($0) }
  }

  // MARK: Tiers and review

  /// Moves a term between 查过 and 要学 (architecture 8.3). Promoting records `day` as the day
  /// it became 要学 and creates its review state, step 0 and due the day after `day`, unless it
  /// is already being learnt; demoting drops both and keeps the review log.
  public func setTier(_ tier: Tier, termID: Int64, on day: LocalDay) throws {
    try db.transaction { () throws(VocabError) in
      guard try db.scalar("SELECT 1 FROM term WHERE id = ?", [.integer(termID)]) != .null else {
        throw VocabError.noSuchTerm(termID)
      }
      switch tier {
      case .learning:
        try promote(termID, on: day)
      case .seen:
        try db.rows(
          "UPDATE term SET tier = 'seen', learning_day = NULL WHERE id = ?", [.integer(termID)])
        try db.rows("DELETE FROM review_state WHERE term_id = ?", [.integer(termID)])
      }
    }
  }

  /// 要学 terms due on or before `day`, earliest first, each with its latest encounter that has
  /// a sentence (architecture 8.5).
  public func dueReviews(on day: LocalDay, limit: Int) throws -> [ReviewItem] {
    try db.rows(
      """
      SELECT \(termColumns), r.step, r.due_day
      FROM review_state r JOIN term t ON t.id = r.term_id
      WHERE t.tier = 'learning' AND r.due_day <= ?
      ORDER BY r.due_day, t.id LIMIT ?
      """, [.text(day.description), .integer(Int64(limit))]
    ).compactMap { row -> ReviewItem? in
      guard let term = Self.term(row), let step = row[termColumnCount].int,
        let due = row[termColumnCount + 1].string.flatMap(LocalDay.init)
      else { return nil }
      let encounter = try db.rows(
        """
        SELECT \(encounterColumns) FROM encounter e
        WHERE e.term_id = ? AND e.sentence IS NOT NULL ORDER BY e.seen_at DESC, e.id DESC LIMIT 1
        """, [.integer(term.id)]
      ).first.flatMap { Self.encounter($0, at: 0) }
      return ReviewItem(term: term, step: step, dueDay: due, encounter: encounter)
    }
  }

  /// Applies a rating on the fixed ladder of architecture 8.5 and logs it: `.good` moves one
  /// step up (capped) and is due `reviewIntervals[step]` days after `day`; `.again` goes back
  /// to step 0, due the next day.
  public func recordReview(
    termID: Int64, encounterID: Int64?, rating: Rating, on day: LocalDay, at date: Date = .now
  ) throws {
    try db.transaction { () throws(VocabError) in
      guard
        let step = try db.scalar(
          "SELECT step FROM review_state WHERE term_id = ?", [.integer(termID)]
        ).int
      else {
        let exists = try db.scalar("SELECT 1 FROM term WHERE id = ?", [.integer(termID)])
        throw exists == .null ? VocabError.noSuchTerm(termID) : VocabError.notLearning(termID)
      }
      let next = rating == .good ? min(step + 1, reviewIntervals.count - 1) : 0
      try db.rows(
        "UPDATE review_state SET step = ?, due_day = ? WHERE term_id = ?",
        [
          .integer(Int64(next)), .text(day.adding(days: reviewIntervals[next]).description),
          .integer(termID),
        ])
      try db.rows(
        "INSERT INTO review_log (term_id, encounter_id, rating, reviewed_at) VALUES (?, ?, ?, ?)",
        [
          .integer(termID), encounterID.map(VocabValue.integer) ?? .null,
          .text(rating.rawValue), .integer(Self.seconds(date)),
        ])
    }
  }

  // MARK: Deleting

  /// Deletes a term with its encounters, review state and review log.
  public func deleteTerm(_ termID: Int64) throws {
    try db.rows("DELETE FROM term WHERE id = ?", [.integer(termID)])
  }

  /// Deletes every lookup and sentence event of `day`, then the 查过 terms left without
  /// encounters. 要学 terms stay with their review state and log; the first and last seen times
  /// of terms that still have encounters are recomputed from what is left.
  public func deleteDay(_ day: LocalDay) throws {
    try db.transaction { () throws(VocabError) in
      try db.rows("DELETE FROM encounter WHERE day = ?", [.text(day.description)])
      try db.rows("DELETE FROM sentence_event WHERE day = ?", [.text(day.description)])
      try db.execute(
        """
        DELETE FROM term WHERE tier = 'seen'
          AND NOT EXISTS (SELECT 1 FROM encounter e WHERE e.term_id = term.id);
        UPDATE term SET
          created_at   = (SELECT min(seen_at) FROM encounter e WHERE e.term_id = term.id),
          last_seen_at = (SELECT max(seen_at) FROM encounter e WHERE e.term_id = term.id)
        WHERE EXISTS (SELECT 1 FROM encounter e WHERE e.term_id = term.id);
        """)
    }
  }

  // MARK: Export

  /// Every term as an Anki-importable TSV (architecture 8.6). The sentence and its translation
  /// come from the latest encounter with a sentence, the sense from that one or else the latest.
  public func exportAnkiTSV() throws -> Data {
    var lines = ["#separator:tab", "#html:true", "#guid column:1", "#tags column:7"]
    for term in try db.rows("SELECT \(termColumns) FROM term t ORDER BY t.id").compactMap({
      Self.term($0)
    }) {
      let encounter = try db.rows(
        """
        SELECT \(encounterColumns) FROM encounter e WHERE e.term_id = ?
        ORDER BY e.sentence IS NOT NULL DESC, e.seen_at DESC, e.id DESC LIMIT 1
        """, [.integer(term.id)]
      ).first.flatMap { Self.encounter($0, at: 0) }
      let apps = try db.rows(
        """
        SELECT DISTINCT source_app FROM encounter
        WHERE term_id = ? AND source_app IS NOT NULL ORDER BY source_app
        """, [.integer(term.id)]
      ).compactMap { $0.first?.string }
      let fields = [
        Self.ankiGUID(language: term.language, lemmaKey: term.lemmaKey),
        Self.html(term.lemma),
        Self.html(term.card.flatMap(Self.phonetic) ?? ""),
        Self.html(encounter?.sense ?? ""),
        encounter.map(Self.highlightedSentence) ?? "",
        Self.html(encounter?.sentenceTranslation ?? ""),
        ([term.language] + apps).map { Self.html($0.replacingOccurrences(of: " ", with: "_")) }
          .joined(separator: " "),
      ]
      lines.append(fields.joined(separator: "\t"))
    }
    return Data((lines.joined(separator: "\n") + "\n").utf8)
  }

  // MARK: Private

  private func reachesPromotion(_ termID: Int64, _ encounterID: Int64, _ rule: AutoPromotion)
    throws(VocabError) -> Bool
  {
    guard
      try db.scalar("SELECT tier FROM term WHERE id = ?", [.integer(termID)])
        == .text(Tier.seen.rawValue)
    else { return false }
    let row = try db.rows(
      """
      SELECT count(*), count(DISTINCT day),
             count(DISTINCT iif(id = ?2, NULL, day))
      FROM encounter WHERE term_id = ?1
      """, [.integer(termID), .integer(encounterID)]
    ).first
    guard let total = row?[0].int, let days = row?[1].int, let daysBefore = row?[2].int else {
      return false
    }
    let meets = { (count: Int, days: Int) in count >= rule.lookups && days >= rule.days }
    // Only the lookup that crosses the threshold promotes, so a term the user moved back to
    // 查过 stays there.
    return meets(total, days) && !meets(total - 1, daysBefore)
  }

  private func promote(_ termID: Int64, on day: LocalDay) throws(VocabError) {
    try db.rows(
      """
      UPDATE term SET
        learning_day = iif(tier = 'learning', coalesce(learning_day, ?2), ?2),
        tier = 'learning'
      WHERE id = ?1
      """, [.integer(termID), .text(day.description)])
    try db.rows(
      "INSERT OR IGNORE INTO review_state (term_id, step, due_day) VALUES (?, 0, ?)",
      [.integer(termID), .text(day.adding(days: reviewIntervals[0]).description)])
  }

  private func summary(_ termID: Int64) throws(VocabError) -> TermSummary? {
    try db.rows("SELECT \(termColumns) FROM term t WHERE t.id = ?", [.integer(termID)])
      .first.flatMap { Self.term($0) }
  }

  private static func open(_ url: URL) throws -> VocabDatabase {
    if let db = try openIfHealthy(url) { return db }
    try moveAside(url)
    return try openIfHealthy(url).orThrow()
  }

  /// Nil when the file is not a sqlite database or is damaged.
  private static func openIfHealthy(_ url: URL) throws(VocabError) -> VocabDatabase? {
    let db = try VocabDatabase(path: url.path)
    do {
      guard try db.scalar("PRAGMA quick_check") == .text("ok") else { return nil }
      try db.execute("PRAGMA foreign_keys = ON")
      try db.rows("PRAGMA journal_mode = WAL")
      try migrate(db)
      return db
    } catch .sqlite(let code, _) where [SQLITE_NOTADB, SQLITE_CORRUPT].contains(code & 0xFF) {
      return nil
    }
  }

  private static func migrate(_ db: VocabDatabase) throws(VocabError) {
    let version = try db.scalar("PRAGMA user_version").int ?? 0
    guard version <= migrations.count else { throw VocabError.newerSchema(version) }
    for next in version..<migrations.count {
      try db.transaction { () throws(VocabError) in
        try db.execute(migrations[next])
        try db.execute("PRAGMA user_version = \(next + 1)")
      }
    }
  }

  /// Renames the file and its `-wal` and `-shm` companions to `<name>.bad-<UTC time>…`; never
  /// deletes them.
  private static func moveAside(_ url: URL) throws {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .gmt
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    let files = FileManager.default
    var stem = url.path + ".bad-" + formatter.string(from: .now)
    var attempt = 1
    while files.fileExists(atPath: stem) {
      attempt += 1
      stem = url.path + ".bad-" + formatter.string(from: .now) + "-\(attempt)"
    }
    for suffix in ["", "-wal", "-shm"] where files.fileExists(atPath: url.path + suffix) {
      try files.moveItem(atPath: url.path + suffix, toPath: stem + suffix)
    }
  }

  private static func seconds(_ date: Date) -> Int64 {
    Int64(date.timeIntervalSince1970.rounded(.down))
  }

  static func date(_ value: VocabValue) -> Date? {
    value.int64.map { Date(timeIntervalSince1970: TimeInterval($0)) }
  }

  private static func withoutQuery(_ url: URL) -> String {
    guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url.absoluteString
    }
    parts.query = nil
    parts.fragment = nil
    return parts.string ?? url.absoluteString
  }

  private static func escapeLike(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "%", with: "\\%")
      .replacingOccurrences(of: "_", with: "\\_")
  }

  static func term(_ row: [VocabValue]) -> TermSummary? {
    guard row.count >= termColumnCount, let id = row[0].int64, let language = row[1].string,
      let lemma = row[2].string, let key = row[3].string,
      let tier = row[4].string.flatMap(Tier.init), let count = row[5].int,
      let created = date(row[8]), let lastSeen = date(row[9])
    else { return nil }
    let card = row[6].string.flatMap { json in
      row[7].int.map { StoredCard(json: json, version: $0) }
    }
    return TermSummary(
      id: id, language: language, lemma: lemma, lemmaKey: key, tier: tier,
      encounterCount: count, card: card, createdAt: created, lastSeenAt: lastSeen)
  }

  static func encounter(_ row: [VocabValue], at offset: Int) -> Encounter? {
    let c = Array(row.dropFirst(offset))
    guard c.count >= 14, let id = c[0].int64, let termID = c[1].int64,
      let kind = c[2].string.flatMap(EncounterKind.init), let surface = c[3].string,
      let source = c[9].string.flatMap(LookupSource.init),
      let day = c[12].string.flatMap(LocalDay.init), let seenAt = date(c[13])
    else { return nil }
    return Encounter(
      id: id, termID: termID, kind: kind, surface: surface, sentence: c[4].string,
      termStart: c[5].int, termLength: c[6].int, sense: c[7].string,
      sentenceTranslation: c[8].string, source: source, sourceApp: c[10].string,
      sourceURL: c[11].string.flatMap(URL.init(string:)), day: day, seenAt: seenAt)
  }

  static func sentenceEvent(_ c: [VocabValue]) -> SentenceEvent? {
    guard c.count >= 11, let id = c[0].int64, let kind = c[1].string.flatMap(SentenceKind.init),
      let source = c[2].string, let result = c[3].string, let applied = c[5].int,
      let sourceLanguage = c[6].string, let resultLanguage = c[7].string,
      let day = c[9].string.flatMap(LocalDay.init), let created = date(c[10])
    else { return nil }
    return SentenceEvent(
      id: id, kind: kind, source: source, result: result, editsJSON: c[4].string,
      applied: applied != 0, sourceLanguage: sourceLanguage, resultLanguage: resultLanguage,
      sourceApp: c[8].string, day: day, createdAt: created)
  }

  // MARK: Anki

  /// Stable across files and imports, so importing again updates notes instead of adding.
  static func ankiGUID(language: String, lemmaKey: String) -> String {
    let digest = SHA256.hash(data: Data("\(language)\u{1F}\(lemmaKey)".utf8))
    return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
  }

  /// HTML-escapes a field; tabs become spaces and line breaks `<br>`.
  static func html(_ text: String) -> String {
    text.replacingOccurrences(of: "\t", with: " ")
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "\r\n", with: "<br>")
      .replacingOccurrences(of: "\n", with: "<br>")
      .replacingOccurrences(of: "\r", with: "<br>")
  }

  /// The encounter's sentence with the term in `<b>`; unmarked when the range does not fit.
  static func highlightedSentence(_ encounter: Encounter) -> String {
    guard let sentence = encounter.sentence else { return "" }
    let units = sentence.utf16
    guard let start = encounter.termStart, let length = encounter.termLength, start >= 0,
      length > 0, start + length <= units.count
    else { return html(sentence) }
    let lower = units.index(units.startIndex, offsetBy: start)
    let upper = units.index(lower, offsetBy: length)
    return html(String(sentence[..<lower])) + "<b>" + html(String(sentence[lower..<upper]))
      + "</b>" + html(String(sentence[upper...]))
  }

  private static func phonetic(_ card: StoredCard) -> String? {
    let object = try? JSONSerialization.jsonObject(with: Data(card.json.utf8))
    return (object as? [String: Any])?["phonetic"] as? String
  }
}

let termColumns = """
  t.id, t.language, t.lemma, t.lemma_key, t.tier,
  (SELECT count(*) FROM encounter c WHERE c.term_id = t.id), t.card_json, t.card_version,
  t.created_at, t.last_seen_at
  """
let termColumnCount = 10

let encounterColumns = """
  e.id, e.term_id, e.kind, e.surface, e.sentence, e.term_start, e.term_length, e.sense,
  e.sentence_translation, e.source_kind, e.source_app, e.source_url, e.day, e.seen_at
  """
let encounterColumnCount = 14

let sentenceColumns = """
  id, kind, source, result, edits_json, applied, source_lang, result_lang, source_app, day,
  created_at
  """

extension Optional {
  fileprivate func orThrow() throws(VocabError) -> Wrapped {
    guard let self else { throw VocabError.sqlite(code: SQLITE_INTERNAL, message: "no row") }
    return self
  }
}
