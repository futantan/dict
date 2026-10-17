// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One rating in the review log: 「上次：记得 · 3 天前」.
public struct ReviewLogEntry: Hashable, Sendable {
  public var rating: Rating
  public var reviewedAt: Date

  public init(rating: Rating, reviewedAt: Date) {
    self.rating = rating
    self.reviewedAt = reviewedAt
  }
}

/// What the review page shows of a term besides its `ReviewItem`.
public struct ReviewHistory: Hashable, Sendable {
  /// The latest encounter with a sentence other than the card's own: 「另一次遇到」.
  public var otherEncounter: Encounter?
  public var lastReview: ReviewLogEntry?

  public init(otherEncounter: Encounter? = nil, lastReview: ReviewLogEntry? = nil) {
    self.otherEncounter = otherEncounter
    self.lastReview = lastReview
  }
}

/// The review page's queries (Design/main-app/review.html), beside `dueReviews` and
/// `recordReview`, which schedule.
extension VocabStore {
  /// A 要学 term as `dueReviews` lists it, due or not, for a review started from 生词本;
  /// nil when the term is not 要学.
  public func reviewItem(termID: Int64) throws -> ReviewItem? {
    guard
      let row = try db.rows(
        """
        SELECT \(termColumns), r.step, r.due_day
        FROM review_state r JOIN term t ON t.id = r.term_id
        WHERE t.tier = 'learning' AND t.id = ?
        """, [.integer(termID)]
      ).first,
      let term = Self.term(row), let step = row[termColumnCount].int,
      let due = row[termColumnCount + 1].string.flatMap(LocalDay.init)
    else { return nil }
    let encounter = try db.rows(
      """
      SELECT \(encounterColumns) FROM encounter e
      WHERE e.term_id = ? AND e.sentence IS NOT NULL ORDER BY e.seen_at DESC, e.id DESC LIMIT 1
      """, [.integer(termID)]
    ).first.flatMap { Self.encounter($0, at: 0) }
    return ReviewItem(term: term, step: step, dueDay: due, encounter: encounter)
  }

  /// The term's latest other sentence, skipping `encounterID` and any encounter with the same
  /// sentence, and its latest review.
  public func reviewHistory(termID: Int64, excluding encounterID: Int64?) throws -> ReviewHistory {
    let excluded = encounterID.map(VocabValue.integer) ?? .null
    let other = try db.rows(
      """
      SELECT \(encounterColumns) FROM encounter e
      WHERE e.term_id = ? AND e.sentence IS NOT NULL AND e.id IS NOT ?
        AND e.sentence IS NOT (SELECT sentence FROM encounter WHERE id = ?)
      ORDER BY e.seen_at DESC, e.id DESC LIMIT 1
      """, [.integer(termID), excluded, excluded]
    ).first.flatMap { Self.encounter($0, at: 0) }
    let last = try db.rows(
      """
      SELECT rating, reviewed_at FROM review_log WHERE term_id = ?
      ORDER BY reviewed_at DESC, id DESC LIMIT 1
      """, [.integer(termID)]
    ).first.flatMap { row -> ReviewLogEntry? in
      guard let rating = row[0].string.flatMap(Rating.init), let date = Self.date(row[1])
      else { return nil }
      return ReviewLogEntry(rating: rating, reviewedAt: date)
    }
    return ReviewHistory(otherEncounter: other, lastReview: last)
  }

  /// The first day after `day` on which a 要学 term is due; nil when none is.
  public func nextDueDay(after day: LocalDay) throws -> LocalDay? {
    try db.scalar(
      """
      SELECT min(r.due_day) FROM review_state r JOIN term t ON t.id = r.term_id
      WHERE t.tier = 'learning' AND r.due_day > ?
      """, [.text(day.description)]
    ).string.flatMap(LocalDay.init)
  }
}
