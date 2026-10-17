// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SQLite3
import Testing

@testable import DictCore

/// A fresh directory under the system temporary directory, one per test.
private func temporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appending(path: "VocabStoreTests-\(UUID())")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func day(_ text: String) -> LocalDay {
  guard let day = LocalDay(text) else { preconditionFailure("bad day \(text)") }
  return day
}

private let monday = day("2026-10-05")
private let tuesday = day("2026-10-06")
private let start = Date(timeIntervalSince1970: 1_791_000_000)

private func lookup(
  _ lemma: String, surface: String? = nil, on day: LocalDay = monday, minute: Int = 0,
  sentence: String? = nil, sense: String? = nil, card: StoredCard? = nil,
  language: String = "en", url: URL? = nil, kind: EncounterKind = .read
) -> LookupRecord {
  let surface = surface ?? lemma
  var termStart: Int?
  if let sentence, let range = sentence.range(of: surface) {
    termStart = sentence.utf16.distance(from: sentence.startIndex, to: range.lowerBound)
  }
  return LookupRecord(
    language: language, lemma: lemma, kind: kind, surface: surface, sentence: sentence,
    termStart: termStart, termLength: termStart.map { _ in surface.utf16.count }, sense: sense,
    sentenceTranslation: sentence.map { "译：\($0)" }, source: .accessibility,
    sourceApp: "com.apple.Safari", sourceURL: url, card: card, day: day,
    seenAt: start.addingTimeInterval(TimeInterval(minute * 60)))
}

private func sentence(_ kind: SentenceKind, on day: LocalDay = monday, minute: Int = 0)
  -> SentenceRecord
{
  SentenceRecord(
    kind: kind, source: "source \(kind.rawValue)", result: "result \(kind.rawValue)",
    editsJSON: kind == .corrected ? #"[{"from":"a","to":"b"}]"# : nil, applied: kind != .translated,
    sourceLanguage: "en", resultLanguage: kind == .translated ? "zh" : "en",
    sourceApp: "com.apple.mail", day: day,
    createdAt: start.addingTimeInterval(TimeInterval(minute * 60)))
}

/// Reads the file directly, bypassing the store.
private func query(_ url: URL, _ sql: String) throws -> [[String?]] {
  var handle: OpaquePointer?
  defer { sqlite3_close(handle) }
  guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
    throw VocabError.sqlite(code: -1, message: "open")
  }
  var statement: OpaquePointer?
  defer { sqlite3_finalize(statement) }
  guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
    throw VocabError.sqlite(code: -1, message: String(cString: sqlite3_errmsg(handle)))
  }
  var rows: [[String?]] = []
  while sqlite3_step(statement) == SQLITE_ROW {
    rows.append(
      (0..<sqlite3_column_count(statement)).map { column in
        sqlite3_column_text(statement, column).map { String(cString: $0) }
      })
  }
  return rows
}

private func count(_ url: URL, _ table: String) throws -> Int {
  try Int(query(url, "SELECT count(*) FROM \(table)")[0][0] ?? "") ?? -1
}

struct VocabStoreSchemaTests {
  @Test func createsAllTablesAndIndexesAtTheLatestVersion() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    _ = try await store.term(language: "en", lemmaKey: "run")

    let tables = try query(url, "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
    #expect(
      tables.map { $0[0] } == ["encounter", "review_log", "review_state", "sentence_event", "term"])
    let indexes = try query(
      url, "SELECT name FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL ORDER BY name")
    #expect(
      indexes.map { $0[0] } == [
        "encounter_day", "encounter_term", "review_log_term", "sentence_event_day",
      ])
    #expect(try query(url, "PRAGMA user_version") == [["2"]])
    #expect(try query(url, "PRAGMA journal_mode") == [["wal"]])
    #expect(VocabStore.schemaVersion == 2)
  }

  @Test func reopensAnExistingFileWithoutLosingRows() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    do {
      let store = try VocabStore(url: url)
      _ = try await store.recordLookup(lookup("run"))
    }
    let store = try VocabStore(url: url)
    let term = try await store.recordLookup(lookup("run", minute: 1))
    #expect(term.encounterCount == 2)
    #expect(try query(url, "PRAGMA user_version") == [["2"]])
  }

  @Test func refusesAFileFromANewerVersion() throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    _ = try VocabStore(url: url)
    var handle: OpaquePointer?
    sqlite3_open(url.path, &handle)
    sqlite3_exec(handle, "PRAGMA user_version = 99", nil, nil, nil)
    sqlite3_close(handle)

    #expect(throws: VocabError.newerSchema(99)) { try VocabStore(url: url) }
    #expect(try query(url, "PRAGMA user_version") == [["99"]])
  }

  @Test(arguments: [
    Data("this is not a database, just some text".utf8),
    Data("SQLite format 3\0".utf8) + Data(repeating: 0xAB, count: 4096),
  ])
  func movesABadFileAsideAndStartsAfresh(contents: Data) async throws {
    let directory = try temporaryDirectory()
    let url = directory.appending(path: "vocab.sqlite")
    try contents.write(to: url)

    let store = try VocabStore(url: url)
    let term = try await store.recordLookup(lookup("run"))
    #expect(term.encounterCount == 1)

    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    let moved = try #require(names.first { $0.hasPrefix("vocab.sqlite.bad-") })
    #expect(try Data(contentsOf: directory.appending(path: moved)) == contents)
    #expect(try count(url, "term") == 1)
    #expect(try query(url, "PRAGMA user_version") == [["2"]])
  }

  @Test func throwsWhenTheDirectoryIsMissing() throws {
    let url = try temporaryDirectory().appending(path: "missing/vocab.sqlite")
    #expect(throws: VocabError.self) { try VocabStore(url: url) }
  }
}

struct VocabStoreLookupTests {
  @Test func countsEachEncounter() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)

    let first = try await store.recordLookup(lookup("run"))
    #expect(first.encounterCount == 1)
    #expect(first.tier == .seen)
    #expect(first.lemma == "run")
    #expect(first.lemmaKey == "run")
    let second = try await store.recordLookup(lookup("run", minute: 5))
    #expect(second.encounterCount == 2)
    #expect(second.id == first.id)
    #expect(second.createdAt == start)
    #expect(second.lastSeenAt == start.addingTimeInterval(300))

    let found = try await store.term(language: "en", lemmaKey: "run")
    #expect(found == second)
    #expect(try await store.term(language: "en", lemmaKey: "walk") == nil)
    #expect(try await store.term(language: "fr", lemmaKey: "run") == nil)
  }

  @Test func mergesSurfacesOfTheSameLemma() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)

    _ = try await store.recordLookup(lookup("run", surface: "ran"))
    _ = try await store.recordLookup(lookup("Run", surface: "running", minute: 1))
    let term = try await store.recordLookup(lookup("run", surface: "Runs", minute: 2))

    #expect(term.encounterCount == 3)
    #expect(term.lemma == "run")
    #expect(try count(url, "term") == 1)
    #expect(
      try query(url, "SELECT surface FROM encounter ORDER BY seen_at").map { $0[0] } == [
        "ran", "running", "Runs",
      ])
  }

  @Test func keepsLanguagesApart() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    _ = try await store.recordLookup(lookup("chat", language: "en"))
    let french = try await store.recordLookup(lookup("chat", language: "fr"))
    #expect(french.encounterCount == 1)
    #expect(try count(url, "term") == 2)
  }

  @Test func storesTheEncounterAsGiven() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    let text = "🙂 He ran home."
    let record = lookup(
      "run", surface: "ran", sentence: text, sense: "跑",
      url: URL(string: "https://example.com/a/b?utm=1&q=x#part"))
    let term = try await store.recordLookup(record)

    let log = try await store.day(monday)
    let encounter = try #require(log.lookups.first?.encounter)
    #expect(encounter.termID == term.id)
    #expect(encounter.kind == .read)
    #expect(encounter.surface == "ran")
    #expect(encounter.sentence == text)
    #expect(encounter.termStart == 6)
    #expect(encounter.termLength == 3)
    #expect(encounter.sense == "跑")
    #expect(encounter.sentenceTranslation == "译：\(text)")
    #expect(encounter.source == .accessibility)
    #expect(encounter.sourceApp == "com.apple.Safari")
    #expect(encounter.sourceURL == URL(string: "https://example.com/a/b"))
    #expect(encounter.day == monday)
    #expect(encounter.seenAt == start)
  }

  @Test func recordsAWordRecalledWhileWriting() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    _ = try await store.recordLookup(lookup("ubiquitous", surface: "无处不在", kind: .produce))
    let encounter = try #require(try await store.day(monday).lookups.first?.encounter)
    #expect(encounter.kind == .produce)
    #expect(encounter.surface == "无处不在")
  }

  @Test func keepsTheLatestCard() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    let card = StoredCard(json: #"{"lemma":"run"}"#, version: 1)
    let newer = StoredCard(json: #"{"lemma":"run","phonetic":"/rʌn/"}"#, version: 2)

    #expect(try await store.recordLookup(lookup("run")).card == nil)
    #expect(try await store.recordLookup(lookup("run", minute: 1, card: card)).card == card)
    #expect(try await store.recordLookup(lookup("run", minute: 2)).card == card)
    #expect(try await store.recordLookup(lookup("run", minute: 3, card: newer)).card == newer)
  }

  @Test func completesALookupWithItsCardLater() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    let card = StoredCard(json: #"{"lemma":"run"}"#, version: 1)
    let first = try await store.record(lookup("run", sentence: "She ran a bakery.", sense: nil))
    let latest = try await store.record(lookup("run", minute: 1))
    _ = try await store.recordLookup(lookup("walk", minute: 2))
    #expect(first.term.encounterCount == 1)
    #expect(latest.term.encounterCount == 2)

    try await store.completeLookup(
      encounterID: first.encounterID, card: card, sense: "经营", sentenceTranslation: "她经营面包店。")

    let lookups = try await store.day(monday).lookups
    #expect(lookups.map(\.encounter.id) == [first.encounterID, latest.encounterID, 3])
    #expect(lookups[0].encounter.sense == "经营")
    #expect(lookups[0].encounter.sentenceTranslation == "她经营面包店。")
    // Only that encounter changes, and the term keeps the card as the latest one.
    #expect(lookups[1].encounter.sense == nil)
    #expect(lookups.map(\.term.card) == [card, card, nil])
    #expect(lookups.map(\.term.encounterCount) == [2, 2, 1])
  }

  @Test func completingAMissingLookupDoesNothing() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    let recorded = try await store.record(lookup("run"))
    try await store.deleteDay(monday)

    try await store.completeLookup(
      encounterID: recorded.encounterID, card: StoredCard(json: "{}", version: 1), sense: "跑",
      sentenceTranslation: nil)
    #expect(try count(url, "encounter") == 0)
    #expect(try count(url, "term") == 0)
  }

  @Test func searchesLemmasAndSensesPrefixFirst() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    _ = try await store.recordLookup(lookup("rerun", minute: 3))
    _ = try await store.recordLookup(lookup("run", minute: 1))
    _ = try await store.recordLookup(lookup("runway", minute: 2))
    _ = try await store.recordLookup(lookup("sprint", minute: 4, sense: "快跑 run fast"))
    _ = try await store.recordLookup(lookup("100%_sure", minute: 5))

    let found = try await store.search("RUN", limit: 10).map(\.lemma)
    #expect(found == ["runway", "run", "sprint", "rerun"])
    #expect(try await store.search("run", limit: 2).map(\.lemma) == ["runway", "run"])
    #expect(try await store.search("跑", limit: 10).map(\.lemma) == ["sprint"])
    #expect(try await store.search("%", limit: 10).map(\.lemma) == ["100%_sure"])
    #expect(try await store.search("0_s", limit: 10).isEmpty)
    #expect(try await store.search("  ", limit: 10).isEmpty)
  }
}

struct VocabStoreTierTests {
  @Test func doesNotPromoteThreeLookupsOnOneDay() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    for minute in 0..<5 {
      _ = try await store.recordLookup(lookup("run", minute: minute))
    }
    #expect(try await store.term(language: "en", lemmaKey: "run")?.tier == .seen)
    #expect(try count(url, "review_state") == 0)
  }

  @Test func doesNotPromoteTwoLookupsOnTwoDays() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    _ = try await store.recordLookup(lookup("run", on: monday))
    let term = try await store.recordLookup(lookup("run", on: tuesday, minute: 1440))
    #expect(term.tier == .seen)
  }

  @Test func promotesTheThirdLookupOnTheSecondDay() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    _ = try await store.recordLookup(lookup("run", on: monday))
    _ = try await store.recordLookup(lookup("run", on: monday, minute: 1))
    let term = try await store.recordLookup(lookup("run", on: tuesday, minute: 1440))
    #expect(term.tier == .learning)
    #expect(
      try query(url, "SELECT term_id, step, due_day FROM review_state") == [
        ["\(term.id)", "0", "2026-10-07"]
      ])
  }

  @Test func promotesOnceThreeSameDayLookupsMeetASecondDay() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    for minute in 0..<3 {
      _ = try await store.recordLookup(lookup("run", on: monday, minute: minute))
    }
    let term = try await store.recordLookup(lookup("run", on: tuesday, minute: 1440))
    #expect(term.tier == .learning)
  }

  @Test func doesNotPromoteAgainAfterTheUserDemotes() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    _ = try await store.recordLookup(lookup("run", on: monday))
    _ = try await store.recordLookup(lookup("run", on: monday, minute: 1))
    let promoted = try await store.recordLookup(lookup("run", on: tuesday, minute: 1440))
    try await store.setTier(.seen, termID: promoted.id, on: tuesday)
    #expect(try count(url, "review_state") == 0)

    let again = try await store.recordLookup(lookup("run", on: day("2026-10-07"), minute: 2880))
    #expect(again.tier == .seen)
  }

  @Test func honoursTheAutoPromotionSetting() async throws {
    let directory = try temporaryDirectory()
    let off = try VocabStore(url: directory.appending(path: "off.sqlite"), autoPromotion: nil)
    let eager = try VocabStore(
      url: directory.appending(path: "eager.sqlite"),
      autoPromotion: AutoPromotion(lookups: 2, days: 1))
    for minute in 0..<2 {
      _ = try await eager.recordLookup(lookup("run", minute: minute))
    }
    for (minute, day) in [(0, monday), (1, monday), (1440, tuesday), (1441, tuesday)] {
      _ = try await off.recordLookup(lookup("run", on: day, minute: minute))
    }
    #expect(try await eager.term(language: "en", lemmaKey: "run")?.tier == .learning)
    #expect(try await off.term(language: "en", lemmaKey: "run")?.tier == .seen)
  }

  @Test func promotesByHandAndDemotes() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    let term = try await store.recordLookup(lookup("run"))

    try await store.setTier(.learning, termID: term.id, on: day("2026-12-31"))
    #expect(try await store.term(language: "en", lemmaKey: "run")?.tier == .learning)
    #expect(try query(url, "SELECT step, due_day FROM review_state") == [["0", "2027-01-01"]])

    // Starring a term that is already being learnt keeps its review progress.
    try await store.recordReview(
      termID: term.id, encounterID: nil, rating: .good, on: day("2027-01-01"), at: start)
    try await store.setTier(.learning, termID: term.id, on: day("2027-01-01"))
    #expect(try query(url, "SELECT step, due_day FROM review_state") == [["1", "2027-01-03"]])

    try await store.setTier(.seen, termID: term.id, on: day("2027-01-01"))
    #expect(try await store.term(language: "en", lemmaKey: "run")?.tier == .seen)
    #expect(try count(url, "review_state") == 0)
    #expect(try count(url, "review_log") == 1)
  }

  @Test func refusesAnUnknownTermOrOneNotBeingLearnt() async throws {
    let store = try VocabStore(url: try temporaryDirectory().appending(path: "vocab.sqlite"))
    await #expect(throws: VocabError.noSuchTerm(42)) {
      try await store.setTier(.learning, termID: 42, on: monday)
    }
    await #expect(throws: VocabError.noSuchTerm(42)) {
      try await store.recordReview(termID: 42, encounterID: nil, rating: .good, on: monday)
    }
    let term = try await store.recordLookup(lookup("run"))
    await #expect(throws: VocabError.notLearning(term.id)) {
      try await store.recordReview(termID: term.id, encounterID: nil, rating: .good, on: monday)
    }
    await #expect(throws: VocabError.emptyLemma) {
      try await store.recordLookup(lookup(" \n"))
    }
  }
}

struct VocabStoreDayTests {
  @Test func recordsEveryKindOfSentenceEvent() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    for (minute, kind) in SentenceKind.allCases.enumerated() {
      try await store.recordSentence(sentence(kind, minute: minute))
    }

    let events = try await store.day(monday).sentences
    #expect(events.map(\.kind) == [.translated, .corrected, .improved, .translatedOut])
    #expect(
      try query(url, "SELECT kind FROM sentence_event ORDER BY created_at").map { $0[0] } == [
        "translated", "corrected", "improved", "translated_out",
      ])
    let corrected = try #require(events.first { $0.kind == .corrected })
    #expect(corrected.source == "source corrected")
    #expect(corrected.result == "result corrected")
    #expect(corrected.editsJSON == #"[{"from":"a","to":"b"}]"#)
    #expect(corrected.applied)
    #expect(corrected.sourceLanguage == "en")
    #expect(corrected.resultLanguage == "en")
    #expect(corrected.sourceApp == "com.apple.mail")
    #expect(corrected.day == monday)
    #expect(corrected.createdAt == start.addingTimeInterval(60))
    #expect(events[0].applied == false)
  }

  @Test func listsOneDayOldestFirst() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    _ = try await store.recordLookup(lookup("walk", on: monday, minute: 2))
    _ = try await store.recordLookup(lookup("run", on: monday, minute: 1))
    _ = try await store.recordLookup(lookup("run", on: tuesday, minute: 1440))
    try await store.recordSentence(sentence(.translated, on: monday, minute: 3))
    try await store.recordSentence(sentence(.improved, on: tuesday, minute: 1441))

    let log = try await store.day(monday)
    #expect(log.day == monday)
    #expect(log.lookups.map(\.term.lemma) == ["run", "walk"])
    #expect(log.lookups[0].term.encounterCount == 2)
    #expect(log.sentences.map(\.kind) == [.translated])

    let tuesdayLog = try await store.day(tuesday)
    #expect(tuesdayLog.lookups.map(\.encounter.day) == [tuesday])
    #expect(tuesdayLog.sentences.map(\.kind) == [.improved])
    let empty = try await store.day(day("2026-10-07"))
    #expect(empty.lookups.isEmpty && empty.sentences.isEmpty)
  }

  @Test func deletingATermCascades() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    let run = try await store.recordLookup(lookup("run"))
    _ = try await store.recordLookup(lookup("run", minute: 1))
    _ = try await store.recordLookup(lookup("walk", minute: 2))
    try await store.setTier(.learning, termID: run.id, on: monday)
    try await store.recordReview(
      termID: run.id, encounterID: nil, rating: .again, on: tuesday, at: start)

    try await store.deleteTerm(run.id)
    #expect(try await store.term(language: "en", lemmaKey: "run") == nil)
    #expect(try query(url, "SELECT count(*) FROM encounter WHERE term_id = \(run.id)") == [["0"]])
    #expect(try count(url, "encounter") == 1)
    #expect(try count(url, "review_state") == 0)
    #expect(try count(url, "review_log") == 0)
    #expect(try await store.term(language: "en", lemmaKey: "walk")?.encounterCount == 1)
  }

  @Test func deletingADayRemovesItsRecordsAndOrphanedTerms() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    _ = try await store.recordLookup(lookup("run", on: monday))
    _ = try await store.recordLookup(lookup("run", on: tuesday, minute: 1440))
    _ = try await store.recordLookup(lookup("walk", on: monday, minute: 1))
    try await store.recordSentence(sentence(.translated, on: monday))
    try await store.recordSentence(sentence(.corrected, on: tuesday, minute: 1441))

    try await store.deleteDay(monday)
    let log = try await store.day(monday)
    #expect(log.lookups.isEmpty && log.sentences.isEmpty)
    #expect(try await store.term(language: "en", lemmaKey: "walk") == nil)
    #expect(try await store.term(language: "en", lemmaKey: "run")?.encounterCount == 1)
    #expect(try count(url, "sentence_event") == 1)
  }

  @Test func deletingADayKeepsTermsBeingLearnt() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    let star = try await store.recordLookup(lookup("star", on: monday))
    _ = try await store.recordLookup(lookup("walk", on: monday, minute: 1))
    try await store.setTier(.learning, termID: star.id, on: monday)
    try await store.recordReview(
      termID: star.id, encounterID: nil, rating: .good, on: tuesday, at: start)

    try await store.deleteDay(monday)
    let kept = try #require(try await store.term(language: "en", lemmaKey: "star"))
    #expect(kept.tier == .learning)
    #expect(kept.encounterCount == 0)
    #expect(kept.createdAt == star.createdAt)
    #expect(try await store.term(language: "en", lemmaKey: "walk") == nil)
    #expect(try count(url, "encounter") == 0)
    #expect(try query(url, "SELECT step, due_day FROM review_state") == [["1", "2026-10-08"]])
    #expect(try count(url, "review_log") == 1)
    let due = try await store.dueReviews(on: day("2026-10-08"), limit: 10)
    #expect(due.map(\.term.id) == [star.id])
  }
}

struct VocabStoreReviewTests {
  @Test func walksTheLadderAndStartsOverOnAgain() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    let term = try await store.recordLookup(lookup("run"))
    try await store.setTier(.learning, termID: term.id, on: monday)

    var today = tuesday
    var dues: [String] = []
    for _ in 0..<8 {
      try await store.recordReview(
        termID: term.id, encounterID: nil, rating: .good, on: today, at: start)
      let row = try query(url, "SELECT step, due_day FROM review_state")[0]
      dues.append("\(row[0] ?? "")@\(row[1] ?? "")")
      today = try #require(LocalDay(row[1] ?? ""))
    }
    #expect(
      dues == [
        "1@2026-10-08", "2@2026-10-12", "3@2026-10-19", "4@2026-11-03", "5@2026-12-03",
        "6@2027-02-01", "6@2027-04-02", "6@2027-06-01",
      ])

    try await store.recordReview(
      termID: term.id, encounterID: nil, rating: .again, on: today, at: start)
    #expect(try query(url, "SELECT step, due_day FROM review_state") == [["0", "2027-06-02"]])
    #expect(try count(url, "review_log") == 9)
  }

  @Test func listsDueTermsWithTheirLatestSentence() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    let run = try await store.recordLookup(lookup("run", sentence: "I run.", sense: "跑"))
    _ = try await store.recordLookup(lookup("run", minute: 1))
    let walk = try await store.recordLookup(lookup("walk", minute: 2))
    _ = try await store.recordLookup(lookup("sit", minute: 3))
    try await store.setTier(.learning, termID: walk.id, on: monday)
    try await store.setTier(.learning, termID: run.id, on: tuesday)

    let due = try await store.dueReviews(on: tuesday, limit: 10)
    #expect(due.map(\.term.lemma) == ["walk"])
    #expect(due[0].encounter == nil)
    #expect(due[0].step == 0)
    #expect(due[0].dueDay == tuesday)

    let later = try await store.dueReviews(on: day("2026-10-07"), limit: 10)
    #expect(later.map(\.term.lemma) == ["walk", "run"])
    #expect(later[1].encounter?.sentence == "I run.")
    #expect(later[1].encounter?.sense == "跑")
    #expect(try await store.dueReviews(on: day("2026-10-07"), limit: 1).count == 1)
  }

  @Test func logsTheEncounterOfAReview() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    let term = try await store.recordLookup(lookup("run", sentence: "I run."))
    try await store.setTier(.learning, termID: term.id, on: monday)
    let encounter = try #require(try await store.dueReviews(on: tuesday, limit: 1).first?.encounter)
    try await store.recordReview(
      termID: term.id, encounterID: encounter.id, rating: .good, on: tuesday, at: start)
    #expect(
      try query(url, "SELECT term_id, encounter_id, rating, reviewed_at FROM review_log") == [
        ["\(term.id)", "\(encounter.id)", "good", "\(Int(start.timeIntervalSince1970))"]
      ])
  }
}

struct VocabStoreExportTests {
  @Test func exportsAnkiTSV() async throws {
    let url = try temporaryDirectory().appending(path: "vocab.sqlite")
    let store = try VocabStore(url: url)
    _ = try await store.recordLookup(
      lookup(
        "run", surface: "ran", sentence: "We ran\t<fast>\nhome.", sense: "跑 & 奔",
        card: StoredCard(json: #"{"phonetic":"/rʌn/"}"#, version: 1)))
    _ = try await store.recordLookup(lookup("walk", minute: 1))

    let text = String(decoding: try await store.exportAnkiTSV(), as: UTF8.self)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(
      Array(lines.prefix(4)) == [
        "#separator:tab", "#html:true", "#guid column:1", "#tags column:7",
      ])
    #expect(lines.count == 7)
    #expect(lines.last == "")
    let run = lines[4].split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    #expect(run.count == 7)
    #expect(run[0].count == 16)
    #expect(
      Array(run.dropFirst()) == [
        "run", "/rʌn/", "跑 &amp; 奔", "We <b>ran</b> &lt;fast&gt;<br>home.",
        "译：We ran &lt;fast&gt;<br>home.", "en com.apple.Safari",
      ])
    let walk = lines[5].split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    #expect(Array(walk.dropFirst()) == ["walk", "", "", "", "", "en com.apple.Safari"])
    #expect(walk[0] != run[0])

    // The same term exports with the same guid from another file.
    let other = try VocabStore(url: try temporaryDirectory().appending(path: "vocab.sqlite"))
    _ = try await other.recordLookup(lookup("Run"))
    let again = String(decoding: try await other.exportAnkiTSV(), as: UTF8.self)
    #expect(again.split(separator: "\n")[4].hasPrefix(run[0] + "\t"))
  }
}
