// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

/// The review page's queries (`VocabStore+Review.swift`).
struct VocabReviewQueryTests {
  private let start = Date(timeIntervalSince1970: 1_791_000_000)
  private var today: LocalDay { LocalDay(start, in: .gmt) }

  private func makeStore() throws -> VocabStore {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "VocabReviewQueryTests-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try VocabStore(url: directory.appending(path: "vocab.sqlite"), autoPromotion: nil)
  }

  private func lookup(_ lemma: String, sentence: String?, minute: Int) -> LookupRecord {
    LookupRecord(
      language: "en", lemma: lemma, surface: lemma, sentence: sentence, source: .accessibility,
      day: today, seenAt: start.addingTimeInterval(TimeInterval(minute * 60)))
  }

  @Test func reviewItemListsALearningTermDueOrNot() async throws {
    let store = try makeStore()
    let term = try await store.recordLookup(
      lookup("hinder", sentence: "Rain hinders us.", minute: 1))
    _ = try await store.recordLookup(lookup("hinder", sentence: nil, minute: 2))
    #expect(try await store.reviewItem(termID: term.id) == nil)

    try await store.setTier(.learning, termID: term.id, on: today)
    let item = try #require(try await store.reviewItem(termID: term.id))

    // Due tomorrow, so not in today's list, but still reviewable; the encounter with a
    // sentence wins over the later one without.
    #expect(try await store.dueReviews(on: today, limit: 10).isEmpty)
    #expect(item.term.id == term.id)
    #expect(item.step == 0)
    #expect(item.dueDay == today.adding(days: 1))
    #expect(item.encounter?.sentence == "Rain hinders us.")
    #expect(try await store.reviewItem(termID: 999) == nil)
  }

  @Test func reviewHistoryTakesAnotherSentenceAndTheLastRating() async throws {
    let store = try makeStore()
    let term = try await store.recordLookup(lookup("discern", sentence: "Old one.", minute: 1))
    _ = try await store.recordLookup(lookup("discern", sentence: "Second one.", minute: 2))
    _ = try await store.recordLookup(lookup("discern", sentence: nil, minute: 3))
    _ = try await store.recordLookup(lookup("discern", sentence: "Latest one.", minute: 4))
    // The same sentence met again is not "another" one.
    _ = try await store.recordLookup(lookup("discern", sentence: "Latest one.", minute: 5))
    try await store.setTier(.learning, termID: term.id, on: today)
    let item = try #require(try await store.reviewItem(termID: term.id))
    let front = try #require(item.encounter)
    #expect(front.sentence == "Latest one.")

    var history = try await store.reviewHistory(termID: term.id, excluding: front.id)
    #expect(history.otherEncounter?.sentence == "Second one.")
    #expect(history.lastReview == nil)

    try await store.recordReview(
      termID: term.id, encounterID: front.id, rating: .again, on: today,
      at: start.addingTimeInterval(600))
    try await store.recordReview(
      termID: term.id, encounterID: front.id, rating: .good, on: today,
      at: start.addingTimeInterval(1200))
    history = try await store.reviewHistory(termID: term.id, excluding: front.id)
    #expect(history.lastReview == ReviewLogEntry(rating: .good, reviewedAt: start + 1200))

    // Without a front sentence, the latest sentence is the other one.
    let all = try await store.reviewHistory(termID: term.id, excluding: nil)
    #expect(all.otherEncounter?.sentence == "Latest one.")
  }

  @Test func nextDueDayIsTheFirstLearningDueAfterTheDay() async throws {
    let store = try makeStore()
    #expect(try await store.nextDueDay(after: today) == nil)
    let early = try await store.recordLookup(lookup("candid", sentence: nil, minute: 1))
    let late = try await store.recordLookup(lookup("feasible", sentence: nil, minute: 2))
    try await store.setTier(.learning, termID: early.id, on: today.adding(days: -5))
    try await store.setTier(.learning, termID: late.id, on: today)
    try await store.recordReview(
      termID: late.id, encounterID: nil, rating: .good, on: today, at: start)

    // `early` is overdue; `late` is due in two days (step 1).
    #expect(try await store.nextDueDay(after: today) == today.adding(days: 2))
    try await store.setTier(.seen, termID: late.id, on: today)
    #expect(try await store.nextDueDay(after: today) == nil)
  }
}
