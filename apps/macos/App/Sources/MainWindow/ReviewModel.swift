// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Observation

/// The review page's state across visits: today's session, recorded through the scheduler
/// as the user rates each word. One per window, held by `WindowData.review`, so leaving the
/// page and coming back keeps the session.
@MainActor @Observable
final class ReviewModel {
  enum Phase: Equatable {
    /// Before the first read.
    case loading
    /// Nothing due; the next day something is, if any.
    case empty(nextDue: LocalDay?)
    case reviewing(ReviewSession)
    /// Every word rated, or ended with 结束; what is still due today is `WindowData.dueCount`.
    case finished(ReviewSession, nextDue: LocalDay?)
  }

  private(set) var phase = Phase.loading
  /// The day the phase was read on; a later day reads again.
  @ObservationIgnored private var day: LocalDay?
  @ObservationIgnored private unowned let data: WindowData

  /// More than anyone reviews in a day; the rest waits for the next session.
  static let sessionLimit = 500

  init(data: WindowData) {
    self.data = data
  }

  var session: ReviewSession? {
    switch phase {
    case .reviewing(let session), .finished(let session, _): session
    case .loading, .empty: nil
    }
  }

  /// When the page shows: starts a session unless one is going or today's has finished.
  func appear() async {
    switch phase {
    case .reviewing: return
    case .finished where day == data.day: return
    default: await start()
    }
  }

  /// A new session of today's due words, `termID` first when given; that term need not be
  /// due, only 要学 (「现在复习」 in 生词本).
  func start(first termID: Int64? = nil) async {
    guard let vocab = data.vocab else {
      phase = .empty(nextDue: nil)
      return
    }
    let today = data.day
    do {
      var items = try await vocab.dueReviews(on: today, limit: Self.sessionLimit)
      if let termID, let first = try await vocab.reviewItem(termID: termID) {
        items.removeAll { $0.term.id == termID }
        items.insert(first, at: 0)
      }
      var cards: [ReviewCard] = []
      for item in items {
        let history = try await vocab.reviewHistory(
          termID: item.term.id, excluding: item.encounter?.id)
        cards.append(ReviewCard(item: item, history: history))
      }
      day = today
      phase =
        cards.isEmpty
        ? .empty(nextDue: try await vocab.nextDueDay(after: today))
        : .reviewing(ReviewSession(cards: cards))
    } catch {
      Log.store.error("reading the reviews failed: \(String(describing: error), privacy: .public)")
      phase = .empty(nextDue: nil)
    }
  }

  func reveal() {
    guard case .reviewing(var session) = phase else { return }
    session.reveal()
    phase = .reviewing(session)
  }

  /// Rates the current word: the first rating of a word goes to the scheduler, and the
  /// sidebar's count is read again. The last one finishes the session.
  func answer(_ rating: Rating) async {
    guard case .reviewing(var session) = phase else { return }
    let card = session.answer(rating)
    phase = .reviewing(session)
    if let card, let vocab = data.vocab {
      do {
        try await vocab.recordReview(
          termID: card.id, encounterID: card.encounter?.id, rating: rating, on: data.day,
          at: data.now())
      } catch {
        Log.store.error("recording a review failed: \(String(describing: error), privacy: .public)")
      }
      await data.refresh()
    }
    if session.isFinished { await finish(session) }
  }

  /// 结束: stops here; what was rated stays recorded.
  func end() async {
    guard case .reviewing(let session) = phase else { return }
    await finish(session)
  }

  private func finish(_ session: ReviewSession) async {
    let next = try? await data.vocab?.nextDueDay(after: data.day)
    phase = .finished(session, nextDue: next ?? nil)
  }
}
