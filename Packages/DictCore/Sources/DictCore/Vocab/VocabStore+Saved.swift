// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A 要学 term as 生词本 shows it (Design/main-app/saved.html): the term, its review state and
/// every time it was met.
public struct SavedTerm: Equatable, Sendable {
  public var term: TermSummary
  /// The latest card, decoded; nil when there is none or it no longer decodes.
  public var card: WordCard?
  /// The day it became 要学; nil for a term learnt before the day was recorded and left
  /// without encounters.
  public var learningDay: LocalDay?
  /// Its rung on the review ladder (`reviewIntervals`) and its next review.
  public var step: Int
  public var dueDay: LocalDay?
  /// Newest first.
  public var encounters: [Encounter]

  /// 「已熟悉」: remembered up to the ladder's top rung, and not forgotten since.
  public var isFamiliar: Bool { step >= reviewIntervals.count - 1 }

  /// The latest meaning recorded with an encounter, else the card's; "" when there is none.
  public var meaning: String {
    encounters.lazy.compactMap(\.sense).first { !$0.isEmpty } ?? card?.definition ?? ""
  }

  /// The latest encounter with a sentence.
  public var latestSentence: Encounter? {
    encounters.first { $0.sentence != nil }
  }
}

/// 生词本's queries. The page filters, sorts and searches the list itself: it holds only the
/// terms being learnt.
extension VocabStore {
  /// Every 要学 term, the most recently met first.
  public func savedTerms() throws -> [SavedTerm] {
    let rows = try db.rows(
      """
      SELECT \(termColumns), t.learning_day, r.step, r.due_day
      FROM term t LEFT JOIN review_state r ON r.term_id = t.id
      WHERE t.tier = 'learning'
      ORDER BY t.last_seen_at DESC, t.id DESC
      """)
    let encounters = Dictionary(
      grouping: try db.rows(
        """
        SELECT \(encounterColumns) FROM encounter e JOIN term t ON t.id = e.term_id
        WHERE t.tier = 'learning' ORDER BY e.seen_at DESC, e.id DESC
        """
      ).compactMap { Self.encounter($0, at: 0) },
      by: \.termID)
    return rows.compactMap { row -> SavedTerm? in
      guard let term = Self.term(row) else { return nil }
      return SavedTerm(
        term: term, card: term.card.flatMap { try? decodeCard($0.json) },
        learningDay: row[termColumnCount].string.flatMap(LocalDay.init),
        step: row[termColumnCount + 1].int ?? 0,
        dueDay: row[termColumnCount + 2].string.flatMap(LocalDay.init),
        encounters: encounters[term.id] ?? [])
    }
  }

  /// 生词本 as CSV (RFC 4180), UTF-8 with a byte order mark so spreadsheets read it as such.
  /// Days are `YYYY-MM-DD` in the user's time zone, as recorded.
  public func exportSavedCSV() throws -> Data {
    let header = [
      "term", "phonetic", "part_of_speech", "meaning", "sentence", "sentence_translation",
      "encounters", "last_seen", "added", "next_review", "familiar", "language",
    ]
    let rows = try savedTerms().map { saved -> [String] in
      let sentence = saved.latestSentence
      return [
        saved.term.lemma, saved.card?.phonetic ?? "", saved.card?.partOfSpeech ?? "",
        saved.meaning, sentence?.sentence ?? "", sentence?.sentenceTranslation ?? "",
        String(saved.term.encounterCount), saved.encounters.first?.day.description ?? "",
        saved.learningDay?.description ?? "", saved.dueDay?.description ?? "",
        saved.isFamiliar ? "yes" : "no", saved.term.language,
      ]
    }
    return Data([0xEF, 0xBB, 0xBF]) + Data(csv([header] + rows).utf8)
  }
}

/// Records as RFC 4180 CSV: each followed by CRLF.
func csv(_ records: [[String]]) -> String {
  records.map { csvRecord($0) + "\r\n" }.joined()
}

/// One record: a field with a comma, a quote or a line break is quoted, its quotes doubled.
func csvRecord(_ fields: [String]) -> String {
  fields.map { field in
    field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" })
      ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
  }.joined(separator: ",")
}
