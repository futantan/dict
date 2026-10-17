// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
  import DictCore
  import Foundation

  /// Sample data for offscreen renders of the main window
  /// (`App/Tests/MainWindow/MainWindowGalleryTests.swift`) and for the pages a later wave
  /// adds: a real `VocabStore` in a temporary file, filled with a week of lookups, sentences
  /// and reviews around a fixed moment, so every query runs as in the app.
  @MainActor
  enum MainWindowGallery {
    /// Saturday 17 October 2026, 14:30 in Shanghai: what the mockups show.
    static let now = Date(timeIntervalSince1970: 1_792_218_600)
    static let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
    static var today: LocalDay { LocalDay(now, in: timeZone) }

    /// The window's data over a filled store.
    static func sampleData() async throws -> WindowData {
      let data = WindowData(vocab: try await sampleStore(), now: { now }, timeZone: { timeZone })
      await data.refresh()
      return data
    }

    /// The window's data over a store with nothing in it.
    static func emptyData() async throws -> WindowData {
      let data = WindowData(vocab: try makeStore(), now: { now }, timeZone: { timeZone })
      await data.refresh()
      return data
    }

    /// The window's data when the log could not be opened.
    static func unavailableData() -> WindowData {
      WindowData(vocab: nil, now: { now }, timeZone: { timeZone })
    }

    static func makeStore() throws -> VocabStore {
      let directory = FileManager.default.temporaryDirectory.appending(
        path: "MainWindowGallery-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      // No automatic promotion: the samples say which words are 要学.
      return try VocabStore(url: directory.appending(path: "vocab.sqlite"), autoPromotion: nil)
    }

    /// 12 words and 5 translations today, 7 corrections and translations out of which 6
    /// replaced the text, 12 words to learn of which 9 are due, and three words met often.
    static func sampleStore() async throws -> VocabStore {
      let store = try makeStore()
      let earlier = today.adding(days: -3)

      // 要学 words promoted earlier, 9 of them due today.
      for (index, word) in learningWords.enumerated() {
        let promoted = index < 9 ? today.adding(days: -3) : today
        let term = try await store.recordLookup(
          lookup(word.lemma, pos: word.pos, sense: word.sense, day: earlier, minutes: index))
        try await store.setTier(.learning, termID: term.id, on: promoted)
      }
      // Met again and again on earlier days, still 查过.
      for (lemma, count) in [("leverage", 5), ("nuance", 4), ("tentative", 3)] {
        for time in 0..<count {
          _ = try await store.recordLookup(
            lookup(
              lemma, pos: "noun", sense: nil, day: today.adding(days: -time - 1), minutes: time))
        }
      }

      // Today, oldest first: nine words this morning, then what the recent list shows.
      for (index, word) in morningWords.enumerated() {
        _ = try await store.recordLookup(
          lookup(word, pos: "noun", sense: nil, day: today, minutes: 8 * 60 + index * 5))
      }
      for index in 0..<5 {
        try await store.recordSentence(
          sentence(
            .translated, "The meeting has been moved to Thursday.", "会议改到周四了。",
            app: "com.apple.Safari", minutes: 9 * 60 + index * 7, applied: false))
      }
      for index in 0..<6 {
        try await store.recordSentence(
          sentence(
            .translatedOut, "我下周去柏林。", "I’m going to Berlin next week.",
            app: "com.apple.mail", minutes: 9 * 60 + 40 + index * 3, applied: index < 5))
      }
      try await store.recordSentence(
        sentence(
          .corrected, "She have lived here since 2019.", "She has lived here since 2019.",
          app: "com.apple.TextEdit", minutes: 10 * 60 + 18, applied: true))
      let mitigate = try await store.recordLookup(
        lookup(
          "mitigate", pos: "verb", sense: "减轻；缓和",
          sentence: "We keep two backups to mitigate the risk of data loss.",
          app: "com.apple.Notes", day: today, minutes: 11 * 60 + 42))
      try await store.setTier(.learning, termID: mitigate.id, on: today)
      _ = try await store.recordLookup(
        lookup(
          "at home", pos: "phrase", sense: "自在",
          sentence: "After two years, she finally feels at home in Berlin.",
          app: "com.apple.mail", day: today, minutes: 13 * 60 + 5))
      let run = try await store.recordLookup(
        lookup(
          "run", pos: "verb", sense: "经营；管理",
          sentence: "She ran a small bakery in the old town.", surface: "ran",
          app: "com.apple.Safari", day: today, minutes: 14 * 60 + 20))
      try await store.setTier(.learning, termID: run.id, on: today)
      return store
    }

    // MARK: Samples

    private static let learningWords: [(lemma: String, pos: String, sense: String)] = [
      ("ubiquitous", "adjective", "无处不在的"), ("meticulous", "adjective", "一丝不苟的"),
      ("alleviate", "verb", "减轻"), ("candid", "adjective", "坦率的"),
      ("discern", "verb", "辨别"), ("feasible", "adjective", "可行的"),
      ("hinder", "verb", "阻碍"), ("inherent", "adjective", "固有的"),
      ("pragmatic", "adjective", "务实的"), ("resilient", "adjective", "有韧性的"),
    ]

    private static let morningWords = [
      "deadline", "draft", "outline", "agenda", "estimate", "invoice", "milestone", "summary",
      "workflow",
    ]

    private static func date(_ day: LocalDay, minutes: Int) -> Date {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = timeZone
      let midnight =
        calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) ?? now
      return midnight.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private static func lookup(
      _ lemma: String, pos: String, sense: String?, sentence: String? = nil,
      surface: String? = nil, app: String = "com.apple.Safari", day: LocalDay, minutes: Int
    ) -> LookupRecord {
      let surface = surface ?? lemma
      let start = sentence.flatMap { text in
        text.range(of: surface).map {
          text.utf16.distance(from: text.startIndex, to: $0.lowerBound)
        }
      }
      return LookupRecord(
        language: "en", lemma: lemma, surface: surface, sentence: sentence, termStart: start,
        termLength: start.map { _ in surface.utf16.count }, sense: sense, source: .accessibility,
        sourceApp: app, card: card(lemma, pos: pos, definition: sense ?? ""), day: day,
        seenAt: date(day, minutes: minutes))
    }

    private static func card(_ lemma: String, pos: String, definition: String) -> StoredCard? {
      let card = WordCard(
        status: .ok, lemma: lemma, phonetic: "", partOfSpeech: pos, definition: definition,
        contextTranslation: "", otherSenses: [], examples: [], collocations: [], level: "")
      guard let data = try? JSONEncoder().encode(card) else { return nil }
      return StoredCard(json: String(decoding: data, as: UTF8.self), version: 1)
    }

    private static func sentence(
      _ kind: SentenceKind, _ source: String, _ result: String, app: String, minutes: Int,
      applied: Bool
    ) -> SentenceRecord {
      SentenceRecord(
        kind: kind, source: source, result: result, applied: applied,
        sourceLanguage: kind == .translatedOut ? "zh-Hans" : "en",
        resultLanguage: kind == .translated ? "zh-Hans" : "en", sourceApp: app, day: today,
        createdAt: date(today, minutes: minutes))
    }
  }
#endif
