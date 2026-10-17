// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

/// The History page's queries and deletes (`VocabStore+History.swift`).
struct VocabHistoryQueryTests {
  private let today = LocalDay(Date(timeIntervalSince1970: 1_791_000_000), in: .gmt)
  private var yesterday: LocalDay { today.adding(days: -1) }
  private let start = Date(timeIntervalSince1970: 1_791_000_000)

  private func makeStore() throws -> VocabStore {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "VocabHistoryQueryTests-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try VocabStore(url: directory.appending(path: "vocab.sqlite"), autoPromotion: nil)
  }

  private func lookup(
    _ lemma: String, surface: String? = nil, on day: LocalDay, minute: Int,
    sentence: String? = nil, sense: String? = nil, translation: String? = nil,
    app: String? = "com.apple.Safari"
  ) -> LookupRecord {
    LookupRecord(
      language: "en", lemma: lemma, surface: surface ?? lemma, sentence: sentence, sense: sense,
      sentenceTranslation: translation, source: .accessibility, sourceApp: app, day: day,
      seenAt: at(minute))
  }

  private func sentence(
    _ kind: SentenceKind, _ source: String = "She have", _ result: String = "She has",
    on day: LocalDay, minute: Int, app: String? = "com.tinyspeck.slackmacgap"
  ) -> SentenceRecord {
    SentenceRecord(
      kind: kind, source: source, result: result, sourceLanguage: "en", resultLanguage: "en",
      sourceApp: app, day: day, createdAt: at(minute))
  }

  private func at(_ minute: Int) -> Date {
    start.addingTimeInterval(TimeInterval(minute * 60))
  }

  /// The ids of a slice as `lookup-…` and `sentence-…`, to compare order.
  private func ids(_ slice: HistorySlice) -> [String] {
    slice.items.map {
      switch $0 {
      case .lookup(let lookup): "lookup-\(lookup.term.lemma)"
      case .sentence(let event): "sentence-\(event.source)"
      }
    }
  }

  @Test func historyMergesBothTablesNewestFirstAndPagesWithACursor() async throws {
    let store = try makeStore()
    _ = try await store.recordLookup(lookup("nuance", on: yesterday, minute: -60))
    try await store.recordSentence(sentence(.translated, "one", on: today, minute: 1))
    _ = try await store.recordLookup(lookup("run", on: today, minute: 2))
    // The same second as `run`: the lookup comes first, as on the Today page.
    try await store.recordSentence(sentence(.corrected, "two", on: today, minute: 2))
    _ = try await store.recordLookup(lookup("mitigate", on: today, minute: 3))

    let first = try await store.history(HistoryFilter(), after: nil, limit: 3)
    #expect(ids(first) == ["lookup-mitigate", "lookup-run", "sentence-two"])
    #expect(first.hasMore)

    let second = try await store.history(
      HistoryFilter(), after: first.items.last.map(HistoryCursor.init), limit: 3)
    #expect(ids(second) == ["sentence-one", "lookup-nuance"])
    #expect(!second.hasMore)

    let exact = try await store.history(HistoryFilter(), after: nil, limit: 5)
    #expect(exact.items.count == 5)
    #expect(!exact.hasMore)
  }

  @Test func historyFiltersByKind() async throws {
    let store = try makeStore()
    _ = try await store.recordLookup(lookup("run", on: today, minute: 1))
    try await store.recordSentence(sentence(.translated, "translated", on: today, minute: 2))
    try await store.recordSentence(sentence(.corrected, "corrected", on: today, minute: 3))
    try await store.recordSentence(sentence(.improved, "improved", on: today, minute: 4))
    try await store.recordSentence(sentence(.translatedOut, "out", on: today, minute: 5))

    func kinds(_ kind: HistoryKind) async throws -> [String] {
      ids(try await store.history(HistoryFilter(kind: kind), after: nil, limit: 10))
    }
    #expect(try await kinds(.all).count == 5)
    #expect(try await kinds(.words) == ["lookup-run"])
    #expect(try await kinds(.translations) == ["sentence-translated"])
    #expect(try await kinds(.corrections) == ["sentence-improved", "sentence-corrected"])
    #expect(try await kinds(.translationsOut) == ["sentence-out"])
  }

  @Test func historySearchesWordsSentencesAndTranslations() async throws {
    let store = try makeStore()
    _ = try await store.recordLookup(
      lookup(
        "run", surface: "ran", on: today, minute: 1, sentence: "She ran a bakery.",
        sense: "经营", translation: "她经营一家面包店。"))
    _ = try await store.recordLookup(lookup("walk", on: today, minute: 2))
    _ = try await store.recordLookup(lookup("100%_sure", on: today, minute: 3))
    try await store.recordSentence(
      sentence(.translated, "The vote was deferred.", "投票推迟了。", on: today, minute: 4))

    func search(_ text: String) async throws -> [String] {
      ids(try await store.history(HistoryFilter(search: text), after: nil, limit: 10))
    }
    #expect(try await search("RUN") == ["lookup-run"])
    #expect(try await search("ran") == ["lookup-run"])
    #expect(try await search("bakery") == ["lookup-run"])
    #expect(try await search("经营") == ["lookup-run"])
    #expect(try await search("面包") == ["lookup-run"])
    #expect(try await search("deferred") == ["sentence-The vote was deferred."])
    #expect(try await search("推迟") == ["sentence-The vote was deferred."])
    // `%` and `_` match themselves.
    #expect(try await search("0%_") == ["lookup-100%_sure"])
    #expect(try await search("  ").count == 4)
  }

  @Test func historyFiltersBySourceAppAndListsTheAppsMostUsedFirst() async throws {
    let store = try makeStore()
    _ = try await store.recordLookup(lookup("run", on: today, minute: 1, app: "com.apple.mail"))
    _ = try await store.recordLookup(lookup("walk", on: today, minute: 2))
    _ = try await store.recordLookup(lookup("swim", on: today, minute: 3, app: nil))
    try await store.recordSentence(sentence(.translated, on: today, minute: 4))
    try await store.recordSentence(sentence(.corrected, on: today, minute: 5))
    try await store.recordSentence(
      sentence(.corrected, "mail", on: today, minute: 6, app: "com.apple.mail"))

    let mail = try await store.history(
      HistoryFilter(sourceApp: "com.apple.mail"), after: nil, limit: 10)
    #expect(ids(mail) == ["sentence-mail", "lookup-run"])
    #expect(
      try await store.historySourceApps()
        == ["com.apple.mail", "com.tinyspeck.slackmacgap", "com.apple.Safari"])
  }

  @Test func historyCountsEverythingAndSinceADay() async throws {
    let store = try makeStore()
    _ = try await store.recordLookup(lookup("run", on: yesterday, minute: -60))
    _ = try await store.recordLookup(lookup("run", on: today, minute: 1))
    try await store.recordSentence(sentence(.translated, on: today, minute: 2))
    try await store.recordSentence(sentence(.translated, on: yesterday, minute: -50))

    #expect(try await store.historyCounts(since: today) == HistoryCounts(total: 4, since: 2))
    #expect(try await store.historyCounts(since: yesterday) == HistoryCounts(total: 4, since: 4))
  }

  @Test func deletingTheOnlyEncounterOfASeenTermDeletesTheTerm() async throws {
    let store = try makeStore()
    let walk = try await store.recordLookup(lookup("walk", on: today, minute: 1))
    let slice = try await store.history(HistoryFilter(), after: nil, limit: 10)
    guard case .lookup(let only) = slice.items.first else {
      Issue.record("no lookup")
      return
    }

    try await store.deleteEncounter(only.encounter.id)

    #expect(try await store.term(language: "en", lemmaKey: walk.lemmaKey) == nil)
    #expect(try await store.history(HistoryFilter(), after: nil, limit: 10).items.isEmpty)
  }

  @Test func deletingAnEncounterKeepsTheTermWhileItHasOthersOrIsLearning() async throws {
    let store = try makeStore()
    _ = try await store.recordLookup(lookup("run", on: yesterday, minute: -60))
    let run = try await store.recordLookup(lookup("run", on: today, minute: 1))
    let learn = try await store.recordLookup(lookup("learn", on: today, minute: 2))
    try await store.setTier(.learning, termID: learn.id, on: today)
    let lookups = try await store.history(HistoryFilter(kind: .words), after: nil, limit: 10)
      .items.compactMap { if case .lookup(let lookup) = $0 { lookup } else { nil } }

    // The latest `run` goes: the term stays, last seen at the one left.
    let latestRun = try #require(lookups.first { $0.term.lemma == "run" })
    try await store.deleteEncounter(latestRun.encounter.id)
    let left = try #require(try await store.term(language: "en", lemmaKey: run.lemmaKey))
    #expect(left.encounterCount == 1)
    #expect(left.lastSeenAt == at(-60))

    // A 要学 term without encounters stays, with its review.
    let learning = try #require(lookups.first { $0.term.lemma == "learn" })
    try await store.deleteEncounter(learning.encounter.id)
    let kept = try #require(try await store.term(language: "en", lemmaKey: learn.lemmaKey))
    #expect(kept.tier == .learning)
    #expect(kept.encounterCount == 0)
    #expect(try await store.dueCount(on: today.adding(days: 1)) == 1)
  }

  @Test func deletingASentenceEventLeavesTheOthers() async throws {
    let store = try makeStore()
    try await store.recordSentence(sentence(.translated, "keep", on: today, minute: 1))
    try await store.recordSentence(sentence(.corrected, "drop", on: today, minute: 2))
    let slice = try await store.history(HistoryFilter(), after: nil, limit: 10)
    guard case .sentence(let drop) = slice.items.first else {
      Issue.record("no sentence")
      return
    }

    try await store.deleteSentenceEvent(drop.id)

    #expect(
      ids(try await store.history(HistoryFilter(), after: nil, limit: 10)) == ["sentence-keep"])
  }
}
