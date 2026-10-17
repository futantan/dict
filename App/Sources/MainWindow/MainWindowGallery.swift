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
          translation: "她在老城区经营一家小面包店。", url: historySourceURL,
          app: "com.apple.Safari", day: today, minutes: 14 * 60 + 20))
      try await store.setTier(.learning, termID: run.id, on: today)
      try await addSavedSamples(to: store)

      // MARK: History (Design/main-app/history.html)
      // `run` met twice before, recorded last so its full card is the one kept; yesterday a
      // correction left unreplaced; on 15 October a translation.
      for (days, minutes) in [(-4, 9 * 60 + 30), (-2, 19 * 60 + 5)] {
        let day = today.adding(days: days)
        _ = try await store.recordLookup(
          LookupRecord(
            language: "en", lemma: "run", surface: "run",
            sentence: "We run a small team of designers.", sense: "经营；管理",
            source: .accessibility, sourceApp: "com.apple.Safari", card: runCard, day: day,
            seenAt: date(day, minutes: minutes)))
      }
      try await store.recordSentence(
        SentenceRecord(
          kind: .corrected, source: "I look forward to hear from you.",
          result: "I look forward to hearing from you.", applied: false, sourceLanguage: "en",
          resultLanguage: "en", sourceApp: "com.apple.mail", day: today.adding(days: -1),
          createdAt: date(today.adding(days: -1), minutes: 16 * 60 + 2)))
      try await store.recordSentence(
        SentenceRecord(
          kind: .translated, source: "Rates are expected to remain elevated through the spring.",
          result: "预计利率在整个春季都将保持高位。", sourceLanguage: "en", resultLanguage: "zh-Hans",
          sourceApp: "com.apple.Safari", day: today.adding(days: -2),
          createdAt: date(today.adding(days: -2), minutes: 9 * 60 + 12)))
      try await addReviewSamples(to: store)
      return store
    }

    /// The page `run` was met on today.
    static let historySourceURL = URL(
      string: "https://www.nytimes.com/2026/10/17/nyregion/queens-bakery.html")

    /// `run`'s card as the model writes it, with other senses and collocations.
    private static var runCard: StoredCard? {
      let card = WordCard(
        status: .ok, lemma: "run", phonetic: "/rʌn/", partOfSpeech: "verb",
        definition: "经营；管理", contextTranslation: "",
        otherSenses: [
          .init(partOfSpeech: "verb", definition: "（机器、程序）运行"),
          .init(partOfSpeech: "noun", definition: "跑步；一段路程"),
        ],
        examples: [],
        collocations: [
          .init(phrase: "run a business", meaning: "经营生意"),
          .init(phrase: "run out of", meaning: "用完"),
          .init(phrase: "run late", meaning: "晚点"),
        ], level: "")
      guard let data = try? JSONEncoder().encode(card) else { return nil }
      return StoredCard(
        json: String(decoding: data, as: UTF8.self), version: WordCard.storedVersion)
    }

    // MARK: - Saved

    /// 生词本's samples: cards with phonetics and other senses, and sentences met on earlier
    /// days, so the Today page's figures stay as they are; one word remembered up to the top
    /// of the ladder, 已熟悉. `run` and `candid` have theirs from History and Review.
    private static func addSavedSamples(to store: VocabStore) async throws {
      for sample in savedSamples {
        for (index, met) in sample.met.enumerated() {
          let day = today.adding(days: -met.daysAgo)
          var record = lookup(
            sample.lemma, pos: sample.pos, sense: sample.definition, sentence: met.sentence,
            translation: met.translation, app: met.app, day: day, minutes: met.minutes)
          record.card = index == sample.met.count - 1 ? savedCard(sample) : nil
          let term = try await store.recordLookup(record)
          if sample.lemma == "resilient", index == 0 {
            for _ in reviewIntervals.indices {
              try await store.recordReview(
                termID: term.id, encounterID: nil, rating: .good, on: today, at: now)
            }
          }
        }
      }
    }

    private struct SavedSample {
      struct Met {
        var sentence: String
        var translation: String
        var app: String
        var daysAgo: Int
        var minutes: Int
      }

      var lemma: String
      var phonetic: String
      var pos: String
      var definition: String
      var otherSenses: [WordCard.Sense] = []
      var met: [Met]
    }

    private static let savedSamples: [SavedSample] = [
      SavedSample(
        lemma: "ubiquitous", phonetic: "/juːˈbɪkwɪtəs/", pos: "adjective",
        definition: "无处不在的；普遍存在的",
        otherSenses: [WordCard.Sense(partOfSpeech: "adjective", definition: "（技术、产品）随处可见的，已普及的")],
        met: [
          .init(
            sentence: "Coffee chains are so ubiquitous here that nobody gives directions by them.",
            translation: "这里连锁咖啡店到处都是，没人拿它们来指路。", app: "com.apple.mail", daysAgo: 8,
            minutes: 8 * 60 + 30),
          .init(
            sentence:
              "Type hints are now ubiquitous across the codebase, so the linter catches most of these.",
            translation: "类型标注如今遍布整个代码库，所以大多数这类问题 linter 都能发现。",
            app: "com.apple.Notes", daysAgo: 2, minutes: 16 * 60 + 48),
          .init(
            sentence:
              "Smartphones have become ubiquitous in classrooms, and teachers are still figuring out the rules.",
            translation: "智能手机在课堂上已经无处不在，老师们还在摸索规则。", app: "com.apple.Safari",
            daysAgo: 1, minutes: 14 * 60 + 2),
        ]),
      SavedSample(
        lemma: "meticulous", phonetic: "/məˈtɪkjələs/", pos: "adjective", definition: "一丝不苟的",
        met: [
          .init(
            sentence: "She keeps meticulous notes on every experiment.",
            translation: "她每次实验都做一丝不苟的记录。", app: "com.apple.Notes", daysAgo: 1,
            minutes: 10 * 60 + 15)
        ]),
      SavedSample(
        lemma: "alleviate", phonetic: "/əˈliːvieɪt/", pos: "verb", definition: "减轻；缓解",
        met: [
          .init(
            sentence: "The new schedule should alleviate some of the pressure on the team.",
            translation: "新的排期应该能减轻团队的一些压力。", app: "com.apple.mail", daysAgo: 2,
            minutes: 9 * 60 + 40)
        ]),
      SavedSample(
        lemma: "feasible", phonetic: "/ˈfiːzəbl/", pos: "adjective", definition: "可行的",
        met: [
          .init(
            sentence: "Is it feasible to ship both features this month?",
            translation: "这个月两个功能都上线可行吗？", app: "com.apple.mail", daysAgo: 4,
            minutes: 11 * 60 + 5)
        ]),
      SavedSample(
        lemma: "resilient", phonetic: "/rɪˈzɪliənt/", pos: "adjective",
        definition: "有韧性的；适应力强的",
        met: [
          .init(
            sentence: "Small teams tend to be more resilient to sudden changes.",
            translation: "小团队往往更能扛住突如其来的变化。", app: "com.apple.Safari", daysAgo: 5,
            minutes: 11 * 60)
        ]),
      SavedSample(
        lemma: "mitigate", phonetic: "/ˈmɪtɪɡeɪt/", pos: "verb", definition: "减轻；缓和",
        met: [
          .init(
            sentence: "Good tests mitigate the risk of a bad release.",
            translation: "好的测试能降低发布出问题的风险。", app: "com.apple.TextEdit", daysAgo: 3,
            minutes: 15 * 60 + 20)
        ]),
    ]

    private static func savedCard(_ sample: SavedSample) -> StoredCard? {
      let card = WordCard(
        status: .ok, lemma: sample.lemma, phonetic: sample.phonetic, partOfSpeech: sample.pos,
        definition: sample.definition, contextTranslation: "", otherSenses: sample.otherSenses,
        examples: [], collocations: [], level: "")
      guard let data = try? JSONEncoder().encode(card) else { return nil }
      return StoredCard(
        json: String(decoding: data, as: UTF8.self), version: WordCard.storedVersion)
    }

    // MARK: Review samples

    /// Two sentences with translations for 「candid」, the fourth word due, and a review of it
    /// three days ago that it failed, so it is still due today; the other due words have no
    /// sentence and ask with the word.
    private static func addReviewSamples(to store: VocabStore) async throws {
      let samples: [(sentence: String, translation: String, app: String, url: URL?, days: Int)] =
        [
          (
            "She gave a candid account of what went wrong at launch.", "她坦率地讲述了发布时出了什么问题。",
            "com.apple.mail", nil, -8
          ),
          (
            "Thanks for being so candid about the delays on your side.", "谢谢你这么坦率地说明你们那边的延误。",
            "com.apple.Safari", URL(string: "https://example.com/notes"), -1
          ),
        ]
      var termID: Int64?
      for sample in samples {
        let day = today.adding(days: sample.days)
        var record = lookup(
          "candid", pos: "adjective", sense: "坦率的", sentence: sample.sentence, app: sample.app,
          day: day, minutes: 16 * 60)
        record.sentenceTranslation = sample.translation
        record.sourceURL = sample.url
        record.card = reviewCard(phonetic: "/ˈkændɪd/")
        termID = try await store.recordLookup(record).id
      }
      if let termID {
        try await store.recordReview(
          termID: termID, encounterID: nil, rating: .again, on: today.adding(days: -3),
          at: date(today.adding(days: -3), minutes: 21 * 60))
      }
    }

    private static func reviewCard(phonetic: String) -> StoredCard? {
      let card = WordCard(
        status: .ok, lemma: "candid", phonetic: phonetic, partOfSpeech: "adjective",
        definition: "坦率的", contextTranslation: "", otherSenses: [], examples: [],
        collocations: [], level: "")
      guard let data = try? JSONEncoder().encode(card) else { return nil }
      return StoredCard(
        json: String(decoding: data, as: UTF8.self), version: WordCard.storedVersion)
    }

    /// The dictionary layer the History page's card shows for `run`, so the renders do not
    /// depend on the dictionary being built.
    static func lexicon(_ term: String, context: String?) -> [LexiconEntry] {
      guard ["run", "ran"].contains(term.lowercased()) else { return [] }
      return [
        LexiconEntry(
          lemma: "run", ipaUS: "/rʌn/", ipaUK: "/rʌn/", band: .common,
          senses: [
            LexiconSense(pos: "verb", gloss: "跑；奔跑", source: "zh"),
            LexiconSense(pos: "verb", gloss: "经营；管理", source: "zh"),
            LexiconSense(pos: "verb", gloss: "（机器、程序）运行", source: "zh"),
            LexiconSense(pos: "noun", gloss: "跑步；一段路程", source: "zh"),
          ])
      ]
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
      surface: String? = nil, translation: String? = nil, url: URL? = nil,
      app: String = "com.apple.Safari", day: LocalDay, minutes: Int
    ) -> LookupRecord {
      let surface = surface ?? lemma
      let start = sentence.flatMap { text in
        text.range(of: surface).map {
          text.utf16.distance(from: text.startIndex, to: $0.lowerBound)
        }
      }
      return LookupRecord(
        language: "en", lemma: lemma, surface: surface, sentence: sentence, termStart: start,
        termLength: start.map { _ in surface.utf16.count }, sense: sense,
        sentenceTranslation: translation, source: .accessibility, sourceApp: app,
        sourceURL: url, card: card(lemma, pos: pos, definition: sense ?? ""), day: day,
        seenAt: date(day, minutes: minutes))
    }

    private static func card(_ lemma: String, pos: String, definition: String) -> StoredCard? {
      let card = WordCard(
        status: .ok, lemma: lemma, phonetic: "", partOfSpeech: pos, definition: definition,
        contextTranslation: "", otherSenses: [], examples: [], collocations: [], level: "")
      guard let data = try? JSONEncoder().encode(card) else { return nil }
      return StoredCard(
        json: String(decoding: data, as: UTF8.self), version: WordCard.storedVersion)
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
