// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import Foundation
import Testing

@testable import DictApp

/// 生词本: what its search, filters and orders keep, its details, and how it stays in step
/// with the sidebar.
@MainActor
struct SavedPageTests {
  private let monday = LocalDay(Date(timeIntervalSince1970: 1_791_172_800), in: .gmt)
  private let start = Date(timeIntervalSince1970: 1_791_172_800)

  private func lookup(_ lemma: String, on day: LocalDay, minute: Int, sense: String? = nil)
    -> LookupRecord
  {
    LookupRecord(
      language: "en", lemma: lemma, surface: lemma, sense: sense, source: .typed, day: day,
      seenAt: start.addingTimeInterval(TimeInterval(minute * 60)))
  }

  /// run: met 3 times, learnt on Monday, due on Tuesday. walk: met once, learnt the week
  /// before, familiar. sit: met twice, learnt on Monday, most recently met.
  private func terms() async throws -> [SavedTerm] {
    let store = try MainWindowGallery.makeStore()
    let run = try await store.recordLookup(lookup("run", on: monday, minute: 0, sense: "跑"))
    _ = try await store.recordLookup(lookup("run", on: monday, minute: 1))
    _ = try await store.recordLookup(lookup("run", on: monday, minute: 2))
    let walk = try await store.recordLookup(lookup("walk", on: monday, minute: 3, sense: "步行"))
    let sit = try await store.recordLookup(lookup("sit", on: monday, minute: 4, sense: "坐"))
    _ = try await store.recordLookup(lookup("sit", on: monday, minute: 5))
    try await store.setTier(.learning, termID: run.id, on: monday)
    try await store.setTier(.learning, termID: walk.id, on: monday.adding(days: -7))
    try await store.setTier(.learning, termID: sit.id, on: monday)
    for _ in reviewIntervals.indices {
      try await store.recordReview(
        termID: walk.id, encounterID: nil, rating: .good, on: monday, at: start)
    }
    try await store.recordReview(
      termID: sit.id, encounterID: nil, rating: .good, on: monday, at: start)
    return try await store.savedTerms()
  }

  @Test func filtersCountBeforeTheSearch() async throws {
    let terms = try await terms()
    let list = SavedList(today: monday.adding(days: 1), weekStart: monday)

    #expect(list.counts(terms) == [.all: 3, .due: 1, .thisWeek: 2, .familiar: 1])
    let names = { (filter: SavedFilter) in
      list.visible(terms, search: "", filter: filter, sort: .lastSeen).map(\.term.lemma)
    }
    #expect(names(.all) == ["sit", "walk", "run"])
    #expect(names(.due) == ["run"])
    #expect(names(.thisWeek) == ["sit", "run"])
    #expect(names(.familiar) == ["walk"])
  }

  @Test func searchesTheWordAndItsMeaning() async throws {
    let terms = try await terms()
    let list = SavedList(today: monday, weekStart: monday)
    let found = { (search: String) in
      list.visible(terms, search: search, filter: .all, sort: .lastSeen).map(\.term.lemma)
    }

    #expect(found("  RU ") == ["run"])
    #expect(found("步") == ["walk"])
    #expect(found("zzz").isEmpty)
  }

  @Test func sortsByLastSeenTimesSeenAndDateAdded() async throws {
    let terms = try await terms()
    let list = SavedList(today: monday, weekStart: monday)
    let sorted = { (sort: SavedSort) in
      list.visible(terms, search: "", filter: .all, sort: sort).map(\.term.lemma)
    }

    #expect(sorted(.lastSeen) == ["sit", "walk", "run"])
    #expect(sorted(.timesSeen) == ["run", "sit", "walk"])
    // Same day: the most recently met first.
    #expect(sorted(.added) == ["sit", "run", "walk"])
  }

  @Test func theWeekStartsOnTheCalendarsFirstWeekday() {
    // Saturday 17 October 2026 in Shanghai.
    var monday = Calendar(identifier: .gregorian)
    monday.firstWeekday = 2
    var sunday = monday
    sunday.firstWeekday = 1
    let now = MainWindowGallery.now
    let zone = MainWindowGallery.timeZone

    #expect(
      SavedList(now: now, timeZone: zone, calendar: monday).weekStart.description == "2026-10-12")
    #expect(
      SavedList(now: now, timeZone: zone, calendar: sunday).weekStart.description == "2026-10-11")
    #expect(SavedList(now: now, timeZone: zone, calendar: sunday).today.description == "2026-10-17")
  }

  @Test func theSentenceHighlightsTheRecordedRange() async throws {
    let store = try MainWindowGallery.makeStore()
    let sentence = "Ran off, she ran home."
    let term = try await store.recordLookup(
      LookupRecord(
        language: "en", lemma: "run", surface: "ran", sentence: sentence, termStart: 13,
        termLength: 3, source: .typed, day: monday, seenAt: start))
    try await store.setTier(.learning, termID: term.id, on: monday)
    let encounter = try #require(try await store.savedTerms().first?.encounters.first)

    let marked = SavedDetail.marked(sentence, encounter: encounter)

    let highlighted = marked.runs.filter { $0.backgroundColor != nil }
      .map { String(marked[$0.range].characters) }
    #expect(highlighted == ["ran"])
    #expect(
      marked.runs.first { $0.backgroundColor != nil }?.range.lowerBound
        == marked.index(marked.startIndex, offsetByCharacters: 13))
  }

  /// The table's 最近遇到 puts the day before the app, so a long app name never hides it.
  @Test func theTableShowsTheDayBeforeTheApp() async throws {
    let store = try MainWindowGallery.makeStore()
    let term = try await store.recordLookup(
      LookupRecord(
        language: "en", lemma: "run", surface: "run", source: .typed,
        sourceApp: "com.apple.Safari", day: monday, seenAt: start))
    try await store.setTier(.learning, termID: term.id, on: monday)
    let encounter = try await store.savedTerms().first?.encounters.first
    let context = SavedRowContext(
      now: start.addingTimeInterval(3 * 86_400), timeZone: .gmt,
      locale: Locale(identifier: "en_US"), appName: { _ in "Safari" })

    #expect(context.lastSeen(encounter) == "Oct 5 · Safari")
    #expect(context.seen(encounter, withTime: false) == "Safari · Oct 5")
  }

  @Test func datesSayTodayAndYesterday() {
    let now = MainWindowGallery.now
    let zone = MainWindowGallery.timeZone
    let locale = Locale(identifier: "en_US")
    let when = { (hours: Double, withTime: Bool) in
      SavedStrings.when(
        now.addingTimeInterval(-hours * 3600), now: now, timeZone: zone, locale: locale,
        withTime: withTime)
    }

    #expect(when(1, false) == "Today")
    #expect(when(1, true).hasPrefix("Today "))
    #expect(when(24, false) == "Yesterday")
    #expect(when(24, true).hasPrefix("Yesterday "))
    #expect(when(24 * 3, false) == "Oct 14")
    #expect(when(24 * 3, true).hasPrefix("Oct 14"))
    #expect(when(24 * 3, true) != "Oct 14")
  }

  @Test func stoppingLearningUpdatesTheListAndTheSidebarTogether() async throws {
    let data = try await MainWindowGallery.sampleData()
    #expect(data.saved.count == data.learningCount)
    #expect(data.saved.count == 12)
    let ubiquitous = try #require(data.saved.first { $0.term.lemma == "ubiquitous" })
    #expect(ubiquitous.encounters.count == 4)
    #expect(ubiquitous.card?.phonetic == "/juːˈbɪkwɪtəs/")
    #expect(data.saved.count { $0.isFamiliar } == 1)

    await data.setTier(.seen, termID: ubiquitous.term.id)

    #expect(data.saved.count == 11)
    #expect(data.learningCount == 11)
    #expect(!data.saved.contains { $0.term.id == ubiquitous.term.id })
  }

  @Test func exportsTheListAsCSV() async throws {
    let data = try await MainWindowGallery.sampleData()
    let csv = try #require(try await data.exportSavedCSV())
    let lines = String(decoding: csv.dropFirst(3), as: UTF8.self).components(separatedBy: "\r\n")
    #expect(lines.first?.hasPrefix("term,phonetic,") == true)
    // A header, twelve words and the empty string after the last line break.
    #expect(lines.count == 14)
  }
}
