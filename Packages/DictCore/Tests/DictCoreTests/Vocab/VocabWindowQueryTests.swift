// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

/// The read-side queries of the main window (`VocabStore+Window.swift`).
struct VocabWindowQueryTests {
  private let today = LocalDay(Date(timeIntervalSince1970: 1_791_000_000), in: .gmt)
  private var yesterday: LocalDay { today.adding(days: -1) }
  private let start = Date(timeIntervalSince1970: 1_791_000_000)

  private func makeStore() throws -> VocabStore {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "VocabWindowQueryTests-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try VocabStore(url: directory.appending(path: "vocab.sqlite"), autoPromotion: nil)
  }

  private func lookup(
    _ lemma: String, on day: LocalDay, minute: Int, app: String? = "com.apple.Safari"
  )
    -> LookupRecord
  {
    LookupRecord(
      language: "en", lemma: lemma, surface: lemma, sentence: "A sentence with \(lemma).",
      source: .accessibility, sourceApp: app, day: day,
      seenAt: start.addingTimeInterval(TimeInterval(minute * 60)))
  }

  private func sentence(_ kind: SentenceKind, on day: LocalDay, minute: Int, applied: Bool)
    -> SentenceRecord
  {
    SentenceRecord(
      kind: kind, source: "She have", result: "She has", applied: applied,
      sourceLanguage: "en", resultLanguage: "en", sourceApp: "com.tinyspeck.slackmacgap",
      day: day, createdAt: start.addingTimeInterval(TimeInterval(minute * 60)))
  }

  @Test func dayCountsSplitLookupsTranslationsAndWrites() async throws {
    let store = try makeStore()
    _ = try await store.recordLookup(lookup("run", on: today, minute: 1))
    _ = try await store.recordLookup(lookup("run", on: today, minute: 2))
    _ = try await store.recordLookup(lookup("mitigate", on: today, minute: 3))
    _ = try await store.recordLookup(lookup("nuance", on: yesterday, minute: -60))
    try await store.recordSentence(sentence(.translated, on: today, minute: 4, applied: false))
    try await store.recordSentence(sentence(.corrected, on: today, minute: 5, applied: true))
    try await store.recordSentence(sentence(.improved, on: today, minute: 6, applied: false))
    try await store.recordSentence(sentence(.translatedOut, on: today, minute: 7, applied: true))
    try await store.recordSentence(sentence(.corrected, on: yesterday, minute: -50, applied: true))

    let counts = try await store.dayCounts(on: today)

    #expect(counts == DayCounts(terms: 2, lookups: 3, translations: 1, writes: 3, replaced: 2))
    #expect(try await store.dayCounts(on: today.adding(days: 1)) == DayCounts())
  }

  @Test func recentActivityMergesLookupsAndSentencesNewestFirst() async throws {
    let store = try makeStore()
    _ = try await store.recordLookup(lookup("nuance", on: yesterday, minute: -60))
    _ = try await store.recordLookup(lookup("run", on: today, minute: 1, app: nil))
    try await store.recordSentence(sentence(.corrected, on: today, minute: 2, applied: true))
    _ = try await store.recordLookup(lookup("mitigate", on: today, minute: 3))

    let recent = try await store.recentActivity(limit: 3)

    #expect(recent.count == 3)
    guard case .lookup(let first) = recent[0], case .sentence(let second) = recent[1],
      case .lookup(let third) = recent[2]
    else {
      Issue.record("unexpected order \(recent)")
      return
    }
    #expect(first.term.lemma == "mitigate")
    #expect(first.encounter.sourceApp == "com.apple.Safari")
    #expect(second.kind == .corrected)
    #expect(third.term.lemma == "run")
    #expect(third.encounter.sourceApp == nil)
    #expect(recent.map(\.date) == recent.map(\.date).sorted(by: >))
    #expect(try await store.recentActivity(limit: 10).count == 4)
  }

  @Test func frequentTermsAreSeenOnesMetAtLeastTwiceMostFirst() async throws {
    let store = try makeStore()
    for minute in 0..<4 {
      _ = try await store.recordLookup(lookup("leverage", on: today, minute: minute))
    }
    for minute in 4..<6 {
      _ = try await store.recordLookup(lookup("nuance", on: today, minute: minute))
    }
    _ = try await store.recordLookup(lookup("once", on: today, minute: 6))
    var learning = try await store.recordLookup(lookup("tentative", on: today, minute: 7))
    learning = try await store.recordLookup(lookup("tentative", on: today, minute: 8))
    learning = try await store.recordLookup(lookup("tentative", on: today, minute: 9))
    try await store.setTier(.learning, termID: learning.id, on: today)

    let frequent = try await store.frequentNotLearning(minEncounters: 2, limit: 5)

    #expect(frequent.map(\.lemma) == ["leverage", "nuance"])
    #expect(frequent.map(\.encounterCount) == [4, 2])
    #expect(try await store.frequentNotLearning(minEncounters: 2, limit: 1).count == 1)
  }

  @Test func dueAndLearningCounts() async throws {
    let store = try makeStore()
    let run = try await store.recordLookup(lookup("run", on: yesterday, minute: -90))
    let walk = try await store.recordLookup(lookup("walk", on: today, minute: 1))
    _ = try await store.recordLookup(lookup("seen", on: today, minute: 2))
    try await store.setTier(.learning, termID: run.id, on: yesterday)
    try await store.setTier(.learning, termID: walk.id, on: today)

    #expect(try await store.learningCount() == 2)
    // Promoted yesterday: due today. Promoted today: due tomorrow.
    #expect(try await store.dueCount(on: today) == 1)
    #expect(try await store.dueCount(on: today.adding(days: 1)) == 2)
  }

  @Test func totalsAndDeleteAll() async throws {
    let store = try makeStore()
    let run = try await store.recordLookup(lookup("run", on: today, minute: 1))
    _ = try await store.recordLookup(lookup("run", on: today, minute: 2))
    _ = try await store.recordLookup(lookup("walk", on: yesterday, minute: -90))
    try await store.recordSentence(sentence(.translated, on: today, minute: 3, applied: false))
    try await store.setTier(.learning, termID: run.id, on: today)
    try await store.recordReview(termID: run.id, encounterID: nil, rating: .good, on: today)

    #expect(try await store.totals() == VocabTotals(terms: 2, sentences: 1))

    try await store.deleteAll()

    #expect(try await store.totals() == VocabTotals(terms: 0, sentences: 0))
    #expect(try await store.learningCount() == 0)
    #expect(try await store.recentActivity(limit: 10).isEmpty)
    // The store keeps working after it is emptied.
    _ = try await store.recordLookup(lookup("again", on: today, minute: 4))
    #expect(try await store.totals() == VocabTotals(terms: 1, sentences: 0))
  }
}
