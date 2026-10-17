// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SQLite3
import Testing

@testable import DictCore

/// The day a term became 要学 (migration 2) and the 生词本's queries (`VocabStore+Saved.swift`).
struct VocabSavedTests {
  private let monday = LocalDay(Date(timeIntervalSince1970: 1_791_172_800), in: .gmt)
  private var tuesday: LocalDay { monday.adding(days: 1) }
  private let start = Date(timeIntervalSince1970: 1_791_000_000)

  private func temporaryFile() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "VocabSavedTests-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "vocab.sqlite")
  }

  private func makeStore(_ url: URL? = nil, autoPromotion: AutoPromotion? = nil) throws
    -> VocabStore
  {
    try VocabStore(url: url ?? temporaryFile(), autoPromotion: autoPromotion)
  }

  private func lookup(
    _ lemma: String, on day: LocalDay, minute: Int, sentence: String? = nil,
    sense: String? = nil, card: WordCard? = nil, app: String? = "com.apple.Safari"
  ) -> LookupRecord {
    let start = sentence.flatMap { text in
      text.range(of: lemma).map { text.utf16.distance(from: text.startIndex, to: $0.lowerBound) }
    }
    let stored = card.flatMap { try? JSONEncoder().encode($0) }.map {
      StoredCard(json: String(decoding: $0, as: UTF8.self), version: 1)
    }
    return LookupRecord(
      language: "en", lemma: lemma, surface: lemma, sentence: sentence, termStart: start,
      termLength: start.map { _ in lemma.utf16.count }, sense: sense,
      sentenceTranslation: sentence.map { "译：\($0)" }, source: .accessibility, sourceApp: app,
      card: stored, day: day, seenAt: self.start.addingTimeInterval(TimeInterval(minute * 60)))
  }

  private func card(_ lemma: String, phonetic: String, pos: String, definition: String)
    -> WordCard
  {
    WordCard(
      status: .ok, lemma: lemma, phonetic: phonetic, partOfSpeech: pos, definition: definition,
      contextTranslation: "", otherSenses: [], examples: [], collocations: [], level: "")
  }

  private func learningDays(_ url: URL) throws -> [[String?]] {
    var handle: OpaquePointer?
    defer { sqlite3_close(handle) }
    guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      throw VocabError.sqlite(code: -1, message: "open")
    }
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    sqlite3_prepare_v2(
      handle, "SELECT lemma, learning_day FROM term ORDER BY id", -1, &statement, nil)
    var rows: [[String?]] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      rows.append((0..<2).map { sqlite3_column_text(statement, $0).map { String(cString: $0) } })
    }
    return rows
  }

  // MARK: Migration

  /// A file written by the first schema, with a 要学 term met on two days, a 查过 term, and a
  /// 要学 term whose encounters were all deleted.
  @Test func migratingAVersionOneFileBackfillsTheFirstEncounterDay() async throws {
    let url = try temporaryFile()
    do {
      let db = try VocabDatabase(path: url.path)
      try db.execute(migrations[0])
      try db.execute(
        """
        INSERT INTO term (id, language, lemma, lemma_key, tier, created_at, last_seen_at)
        VALUES (1, 'en', 'run', 'run', 'learning', 100, 200),
               (2, 'en', 'walk', 'walk', 'seen', 100, 100),
               (3, 'en', 'sit', 'sit', 'learning', 100, 100);
        INSERT INTO encounter (term_id, kind, surface, source_kind, day, seen_at)
        VALUES (1, 'read', 'run', 'typed', '2026-10-06', 200),
               (1, 'read', 'ran', 'typed', '2026-10-05', 100),
               (2, 'read', 'walk', 'typed', '2026-10-05', 100);
        INSERT INTO review_state (term_id, step, due_day)
        VALUES (1, 6, '2026-12-01'), (3, 0, '2026-10-06');
        PRAGMA user_version = 1;
        """)
    }

    let store = try makeStore(url)

    #expect(
      try learningDays(url) == [["run", "2026-10-05"], ["walk", nil], ["sit", nil]])
    let saved = try await store.savedTerms()
    #expect(saved.map(\.term.lemma) == ["run", "sit"])
    #expect(saved.map(\.learningDay) == [monday, nil])
    #expect(saved[0].isFamiliar)
    #expect(saved[0].encounters.map(\.surface) == ["run", "ran"])
    #expect(VocabStore.schemaVersion == 2)
  }

  // MARK: The day a term became 要学

  @Test func recordsTheDayATermBecomesLearningAndKeepsItWhenStarredAgain() async throws {
    let url = try temporaryFile()
    let store = try makeStore(url)
    let run = try await store.recordLookup(lookup("run", on: monday, minute: 0))

    try await store.setTier(.learning, termID: run.id, on: monday)
    try await store.setTier(.learning, termID: run.id, on: tuesday)
    #expect(try learningDays(url) == [["run", "2026-10-05"]])

    try await store.setTier(.seen, termID: run.id, on: tuesday)
    #expect(try learningDays(url) == [["run", nil]])

    try await store.setTier(.learning, termID: run.id, on: tuesday)
    #expect(try learningDays(url) == [["run", "2026-10-06"]])
  }

  @Test func automaticPromotionRecordsTheDayToo() async throws {
    let url = try temporaryFile()
    let store = try makeStore(url, autoPromotion: AutoPromotion(lookups: 2, days: 2))
    _ = try await store.recordLookup(lookup("run", on: monday, minute: 0))
    let term = try await store.recordLookup(lookup("run", on: tuesday, minute: 1440))

    #expect(term.tier == .learning)
    #expect(try learningDays(url) == [["run", "2026-10-06"]])
  }

  // MARK: 生词本

  @Test func listsLearningTermsWithReviewStateAndEveryEncounter() async throws {
    let store = try makeStore()
    let run = try await store.recordLookup(
      lookup(
        "run", on: monday, minute: 0, sentence: "We run daily.", sense: "跑",
        card: card("run", phonetic: "/rʌn/", pos: "verb", definition: "跑步")))
    _ = try await store.recordLookup(
      lookup("run", on: tuesday, minute: 1440, sense: "经营", app: nil))
    let walk = try await store.recordLookup(lookup("walk", on: monday, minute: 5))
    _ = try await store.recordLookup(lookup("sit", on: tuesday, minute: 1500))
    try await store.setTier(.learning, termID: run.id, on: monday)
    try await store.setTier(.learning, termID: walk.id, on: tuesday)
    for day in 0..<6 {
      try await store.recordReview(
        termID: walk.id, encounterID: nil, rating: .good, on: tuesday.adding(days: day),
        at: start)
    }

    let saved = try await store.savedTerms()

    // Most recently met first; 查过 terms are left out.
    #expect(saved.map(\.term.lemma) == ["run", "walk"])
    let first = saved[0]
    #expect(first.term.encounterCount == 2)
    #expect(first.encounters.map(\.sense) == ["经营", "跑"])
    #expect(first.encounters.map(\.sourceApp) == [nil, "com.apple.Safari"])
    #expect(first.encounters[1].sentence == "We run daily.")
    #expect(first.card?.phonetic == "/rʌn/")
    #expect(first.card?.partOfSpeech == "verb")
    #expect(first.meaning == "经营")
    #expect(first.learningDay == monday)
    #expect(first.step == 0)
    #expect(first.dueDay == tuesday)
    #expect(!first.isFamiliar)
    let second = saved[1]
    #expect(second.meaning == "")
    #expect(second.step == reviewIntervals.count - 1)
    #expect(second.isFamiliar)
  }

  @Test func theMeaningFallsBackToTheCard() async throws {
    let store = try makeStore()
    let run = try await store.recordLookup(
      lookup(
        "run", on: monday, minute: 0,
        card: card("run", phonetic: "", pos: "verb", definition: "跑步")))
    try await store.setTier(.learning, termID: run.id, on: monday)

    #expect(try await store.savedTerms().first?.meaning == "跑步")
  }

  // MARK: CSV

  @Test func csvQuotesOnlyWhatNeedsIt() {
    #expect(
      csvRecord(["plain", "", "a,b", "say \"hi\"", "two\nlines", "cr\rhere"])
        == "plain,,\"a,b\",\"say \"\"hi\"\"\",\"two\nlines\",\"cr\rhere\"")
    #expect(csv([["a", "b"], ["1", "2"]]) == "a,b\r\n1,2\r\n")
    #expect(csv([]) == "")
  }

  @Test func exportsTheLearningTermsAsCSV() async throws {
    let store = try makeStore()
    let run = try await store.recordLookup(
      lookup(
        "run", on: monday, minute: 0, sentence: "We run, \"daily\".", sense: "跑",
        card: card("run", phonetic: "/rʌn/", pos: "verb", definition: "跑步")))
    _ = try await store.recordLookup(lookup("run", on: tuesday, minute: 1440))
    _ = try await store.recordLookup(lookup("walk", on: monday, minute: 5))
    try await store.setTier(.learning, termID: run.id, on: tuesday)

    let data = try await store.exportSavedCSV()

    // A byte order mark first, so spreadsheets read the UTF-8 meanings correctly.
    #expect(data.prefix(3) == Data([0xEF, 0xBB, 0xBF]))
    let text = String(decoding: data.dropFirst(3), as: UTF8.self)
    #expect(
      text == """
        term,phonetic,part_of_speech,meaning,sentence,sentence_translation,encounters,\
        last_seen,added,next_review,familiar,language\r
        run,/rʌn/,verb,跑,"We run, ""daily"".","译：We run, ""daily"".",2,2026-10-06,\
        2026-10-06,2026-10-07,no,en\r

        """)
  }
}
