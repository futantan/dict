// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Testing

@testable import DictApp

/// The review page's session (`ReviewSession`), its model over a real store (`ReviewModel`)
/// and its wording of days.
@MainActor
struct ReviewTests {
  private let today = MainWindowGallery.today

  /// Due cards for `lemmas` from a real store, in the scheduler's order; a lemma's sentence,
  /// if any, has no recorded range.
  private func cards(_ lemmas: [String], sentences: [String: String] = [:]) async throws
    -> [ReviewCard]
  {
    let store = try MainWindowGallery.makeStore()
    for (index, lemma) in lemmas.enumerated() {
      let term = try await store.recordLookup(
        LookupRecord(
          language: "en", lemma: lemma, surface: lemma, sentence: sentences[lemma],
          source: .typed, day: today.adding(days: -2),
          seenAt: MainWindowGallery.now.addingTimeInterval(TimeInterval(index * 60 - 2 * 86_400))))
      try await store.setTier(.learning, termID: term.id, on: today.adding(days: -2))
    }
    return try await store.dueReviews(on: today, limit: 10).map { ReviewCard(item: $0) }
  }

  // MARK: Session

  @Test func aSessionRatesEachWordOnceAndBringsAForgottenOneBackOnce() async throws {
    let cards = try await cards(["alpha", "beta", "gamma"])
    var session = ReviewSession(cards: cards + [cards[0]])
    #expect(session.total == 3)
    #expect(session.current?.lemma == "alpha")

    // Nothing is rated before the answer shows.
    #expect(session.answer(.good) == nil)
    #expect(session.reviewed == 0)

    session.reveal()
    #expect(session.answer(.again)?.lemma == "alpha")
    #expect(!session.isRevealed)
    session.reveal()
    #expect(session.answer(.good)?.lemma == "beta")
    session.reveal()
    #expect(session.answer(.good)?.lemma == "gamma")
    #expect(session.reviewed == 3)
    #expect((session.remembered, session.forgotten) == (2, 1))

    // alpha again, at the end: practice, not recorded, and not put back a second time.
    #expect(session.current?.lemma == "alpha")
    #expect(session.isRepeat)
    session.reveal()
    #expect(session.answer(.again) == nil)
    #expect(session.isFinished)
    #expect((session.reviewed, session.remembered, session.forgotten) == (3, 2, 1))
  }

  @Test func theFrontIsTheSentenceWithAGapOrElseTheWord() async throws {
    let cards = try await cards(
      ["mitigate", "hinder", "candid"],
      sentences: ["mitigate": "Backups Mitigate the risk.", "hinder": "Nothing to see."])
    let mitigate = try #require(cards.first { $0.lemma == "mitigate" })
    // No recorded range: found by the word as it appeared, ignoring case.
    #expect(mitigate.cloze == Cloze(before: "Backups ", term: "Mitigate", after: " the risk."))
    #expect(cards.first { $0.lemma == "hinder" }?.cloze == nil)
    #expect(cards.first { $0.lemma == "candid" }?.cloze == nil)
  }

  @Test func theGallerysCandidAsksWithItsLatestSentence() async throws {
    let data = try await MainWindowGallery.sampleData()
    await data.review.appear()
    let session = try #require(data.review.session)
    let candid = try #require(session.queue.first { $0.lemma == "candid" })
    #expect(
      candid.cloze
        == Cloze(
          before: "Thanks for being so ", term: "candid", after: " about the delays on your side."))
    #expect(candid.sense == "坦率的")
    #expect(candid.partOfSpeech == "adjective")
    #expect(candid.phonetic == "/ˈkændɪd/")
    #expect(candid.encounter?.sentenceTranslation == "谢谢你这么坦率地说明你们那边的延误。")
    #expect(candid.history.otherEncounter?.sourceApp == "com.apple.mail")
    #expect(candid.history.lastReview?.rating == .again)
  }

  // MARK: Model

  @Test func theModelRecordsFirstRatingsAndFinishesWithTheNextDay() async throws {
    let data = try await MainWindowGallery.sampleData()
    let model = data.review
    #expect(model.phase == .loading)
    await model.appear()
    var session = try #require(model.session)
    #expect(session.total == 9)
    #expect(data.dueCount == 9)

    model.reveal()
    await model.answer(.again)
    // Rated 忘了: due tomorrow, so the sidebar's badge drops.
    #expect(data.dueCount == 8)
    for _ in 1..<9 {
      model.reveal()
      await model.answer(.good)
    }
    session = try #require(model.session)
    #expect(session.current?.id == session.queue.first?.id)
    #expect(session.isRepeat)
    model.reveal()
    await model.answer(.good)

    // The repeat is not recorded: the first word is still due tomorrow, at step 0.
    #expect(data.dueCount == 0)
    #expect(model.phase == .finished(try #require(model.session), nextDue: today.adding(days: 1)))
    let vocab = try #require(data.vocab)
    // Tomorrow: the forgotten word, and two of the three marked to learn today; the third,
    // `resilient`, 生词本's samples remembered up to the top of the ladder.
    let tomorrow = try await vocab.dueReviews(on: today.adding(days: 1), limit: 20)
    #expect(tomorrow.map(\.term.lemma).sorted() == ["mitigate", "run", "ubiquitous"])
    // Leaving and coming back the same day keeps the finished session.
    await model.appear()
    #expect(model.session?.reviewed == 9)
  }

  @Test func endingEarlyKeepsWhatWasRatedAndWhatIsStillDue() async throws {
    let data = try await MainWindowGallery.sampleData()
    let model = data.review
    await model.appear()
    model.reveal()
    await model.answer(.good)
    await model.end()

    guard case .finished(let session, _) = model.phase else {
      Issue.record("not finished: \(model.phase)")
      return
    }
    #expect(session.reviewed == 1)
    #expect(data.dueCount == 8)
    await model.start()
    #expect(model.session?.total == 8)
  }

  @Test func aReviewStartedFromTheWordListPutsThatWordFirst() async throws {
    let data = try await MainWindowGallery.sampleData()
    let vocab = try #require(data.vocab)
    let runID = try #require(
      data.today.recent.lazy.compactMap { activity -> Int64? in
        guard case .lookup(let lookup) = activity, lookup.term.lemma == "run" else { return nil }
        return lookup.term.id
      }.first)
    let run = try #require(try await vocab.reviewItem(termID: runID))

    let navigation = MainNavigation()
    navigation.startReview(with: run.term.id)
    #expect(navigation.section == .review)
    #expect(navigation.reviewTermRequest == run.term.id)
    await data.review.start(first: run.term.id)
    navigation.didStartReview()
    #expect(navigation.reviewTermRequest == nil)

    // Not due until tomorrow, yet first, before the nine due today.
    let session = try #require(data.review.session)
    #expect(session.current?.lemma == "run")
    #expect(session.total == 10)
    #expect(session.current?.cloze?.term == "ran")
  }

  @Test func nothingDueIsTheEmptyState() async throws {
    let empty = try await MainWindowGallery.emptyData()
    await empty.review.appear()
    #expect(empty.review.phase == .empty(nextDue: nil))

    let unavailable = MainWindowGallery.unavailableData()
    await unavailable.review.appear()
    #expect(unavailable.review.phase == .empty(nextDue: nil))
  }

  // MARK: Wording

  /// The hints under the card name only the keys that work: Space before the answer shows,
  /// 1 and 2 after; P where pronouncing does not give the answer away.
  @Test func theKeyHintsFollowTheCard() {
    let keys = { (isRevealed: Bool, canPronounce: Bool) in
      KeyHint.current(isRevealed: isRevealed, canPronounce: canPronounce).map(\.key)
    }
    #expect(keys(false, false) == [ReviewStrings.spaceKey])
    #expect(keys(false, true) == [ReviewStrings.spaceKey, "P"])
    #expect(keys(true, true) == ["1", "2", "P"])
    #expect(
      KeyHint.current(isRevealed: true, canPronounce: true).map(\.title)
        == [ReviewStrings.forgot, ReviewStrings.remembered, ReviewStrings.pronounce])
  }

  /// During a session the header counts the session's words, as 「3 / 9」 does; the sidebar's
  /// badge and the header out of a session count what is still due.
  @Test func theHeaderCountsTheSession() {
    #expect(ReviewStrings.thisSession(9) == "Word List · 9 words this session")
    #expect(ReviewStrings.thisSession(1) == "Word List · 1 word this session")
  }

  @Test func daysReadAsTheInterfaceSaysThem() {
    let english = Locale(identifier: "en_US")
    let threeDaysAgo = MainWindowGallery.now.addingTimeInterval(-3 * 86_400 - 3600)
    #expect(
      ReviewDates.ago(
        threeDaysAgo, today: today, timeZone: MainWindowGallery.timeZone, locale: english)
        == "3 days ago")
    #expect(
      ReviewDates.ago(
        MainWindowGallery.now, today: today, timeZone: MainWindowGallery.timeZone, locale: english)
        == "today")
    #expect(ReviewDates.next(today.adding(days: 1), today: today, locale: english) == "tomorrow")
    #expect(ReviewDates.next(today.adding(days: 4), today: today, locale: english) == "Oct 21")
    #expect(
      ReviewDates.day(today.adding(days: 90), today: today, locale: english) == "Jan 15, 2027")
  }
}
