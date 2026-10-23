// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A calendar date `YYYY-MM-DD` in the user's time zone, computed by the caller (architecture
/// 8.7). The store only compares, stores and adds days to it and never looks at a time zone.
public struct LocalDay: Hashable, Comparable, Sendable, CustomStringConvertible {
  public let year: Int
  public let month: Int
  public let day: Int

  /// Nil unless the components form a real Gregorian date in years 1–9999.
  public init?(year: Int, month: Int, day: Int) {
    guard (1...9999).contains(year), let date = Self.date(year, month, day) else { return nil }
    let parts = Self.gmt.dateComponents([.year, .month, .day], from: date)
    guard parts.year == year, parts.month == month, parts.day == day else { return nil }
    (self.year, self.month, self.day) = (year, month, day)
  }

  /// Parses exactly `YYYY-MM-DD`.
  public init?(_ text: String) {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
    else { return nil }
    self.init(year: year, month: month, day: day)
  }

  /// The date of `date` in `timeZone`: the one place a time zone enters, on the caller's side.
  public init(_ date: Date, in timeZone: TimeZone) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    (year, month, day) = (parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
  }

  public var description: String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }

  public func adding(days: Int) -> LocalDay {
    guard let start = Self.date(year, month, day),
      let end = Self.gmt.date(byAdding: .day, value: days, to: start)
    else { return self }
    return LocalDay(end, in: .gmt)
  }

  public static func < (a: LocalDay, b: LocalDay) -> Bool {
    (a.year, a.month, a.day) < (b.year, b.month, b.day)
  }

  private static let gmt: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()

  private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date? {
    gmt.date(from: DateComponents(year: year, month: month, day: day))
  }
}

/// 查过 / 要学 (architecture 8.3).
public enum Tier: String, Sendable, CaseIterable {
  case seen
  case learning
}

public enum EncounterKind: String, Sendable, CaseIterable {
  /// Looked up while reading.
  case read
  /// Picked as the foreign word for a word in my language while writing.
  case produce
}

/// How the text reached the app; mirrors the app's capture sources.
public enum LookupSource: String, Sendable, CaseIterable {
  case accessibility
  case menuCopy
  case keyCopy
  case ocr
  case typed
}

public enum SentenceKind: String, Sendable, CaseIterable {
  case translated
  case corrected
  case improved
  case translatedOut = "translated_out"
}

public enum Rating: String, Sendable, CaseIterable {
  case again
  case good
}

/// A term's latest model card, kept to show again without a request.
public struct StoredCard: Hashable, Sendable {
  public var json: String
  /// The version of the `WordCard` structure.
  public var version: Int

  public init(json: String, version: Int) {
    self.json = json
    self.version = version
  }
}

/// One lookup to record (architecture 8.1).
public struct LookupRecord: Sendable {
  /// The language subtag, for example `en`.
  public var language: String
  /// The lemma found on device; the store keys the term by `normalizedKey(lemma)`.
  public var lemma: String
  public var kind: EncounterKind
  /// The text as it appeared; for `.produce` the word in my language.
  public var surface: String
  public var sentence: String?
  /// The term's UTF-16 offset and length in `sentence`.
  public var termStart: Int?
  public var termLength: Int?
  /// The meaning in this sentence, in my language.
  public var sense: String?
  public var sentenceTranslation: String?
  public var source: LookupSource
  /// Bundle id.
  public var sourceApp: String?
  /// Stored without its query and fragment.
  public var sourceURL: URL?
  /// When nil the term keeps its previous card.
  public var card: StoredCard?
  public var day: LocalDay
  public var seenAt: Date

  public init(
    language: String, lemma: String, kind: EncounterKind = .read, surface: String,
    sentence: String? = nil, termStart: Int? = nil, termLength: Int? = nil, sense: String? = nil,
    sentenceTranslation: String? = nil, source: LookupSource, sourceApp: String? = nil,
    sourceURL: URL? = nil, card: StoredCard? = nil, day: LocalDay, seenAt: Date
  ) {
    self.language = language
    self.lemma = lemma
    self.kind = kind
    self.surface = surface
    self.sentence = sentence
    self.termStart = termStart
    self.termLength = termLength
    self.sense = sense
    self.sentenceTranslation = sentenceTranslation
    self.source = source
    self.sourceApp = sourceApp
    self.sourceURL = sourceURL
    self.card = card
    self.day = day
    self.seenAt = seenAt
  }
}

/// One finished sentence translation, correction or rewrite (architecture 8.1).
public struct SentenceRecord: Sendable {
  public var kind: SentenceKind
  public var source: String
  public var result: String
  /// The correction's list of edits.
  public var editsJSON: String?
  /// Whether the result replaced the text in the other app.
  public var applied: Bool
  public var sourceLanguage: String
  public var resultLanguage: String
  public var sourceApp: String?
  public var day: LocalDay
  public var createdAt: Date

  public init(
    kind: SentenceKind, source: String, result: String, editsJSON: String? = nil,
    applied: Bool = false, sourceLanguage: String, resultLanguage: String,
    sourceApp: String? = nil, day: LocalDay, createdAt: Date
  ) {
    self.kind = kind
    self.source = source
    self.result = result
    self.editsJSON = editsJSON
    self.applied = applied
    self.sourceLanguage = sourceLanguage
    self.resultLanguage = resultLanguage
    self.sourceApp = sourceApp
    self.day = day
    self.createdAt = createdAt
  }
}

public struct TermSummary: Hashable, Sendable {
  public var id: Int64
  public var language: String
  public var lemma: String
  public var lemmaKey: String
  public var tier: Tier
  /// How many times the term has been met, the latest included: 「第 N 次」.
  public var encounterCount: Int
  public var card: StoredCard?
  public var createdAt: Date
  public var lastSeenAt: Date
}

/// A lookup just recorded: its term, the count including it, and the new encounter.
public struct RecordedLookup: Hashable, Sendable {
  public var term: TermSummary
  public var encounterID: Int64
}

public struct Encounter: Hashable, Sendable {
  public var id: Int64
  public var termID: Int64
  public var kind: EncounterKind
  public var surface: String
  public var sentence: String?
  public var termStart: Int?
  public var termLength: Int?
  public var sense: String?
  public var sentenceTranslation: String?
  public var source: LookupSource
  public var sourceApp: String?
  public var sourceURL: URL?
  public var day: LocalDay
  public var seenAt: Date
}

public struct SentenceEvent: Hashable, Sendable {
  public var id: Int64
  public var kind: SentenceKind
  public var source: String
  public var result: String
  public var editsJSON: String?
  public var applied: Bool
  public var sourceLanguage: String
  public var resultLanguage: String
  public var sourceApp: String?
  public var day: LocalDay
  public var createdAt: Date
}

/// Everything recorded on one day, oldest first (architecture 8.4).
public struct DailyLog: Hashable, Sendable {
  public struct Lookup: Hashable, Sendable {
    public var term: TermSummary
    public var encounter: Encounter
  }

  public var day: LocalDay
  public var lookups: [Lookup]
  public var sentences: [SentenceEvent]
}

/// A 要学 term due for review with its latest encounter that has a sentence (architecture 8.5).
public struct ReviewItem: Hashable, Sendable {
  public var term: TermSummary
  public var step: Int
  public var dueDay: LocalDay
  public var encounter: Encounter?
}

/// The automatic promotion to 要学: `lookups` lookups spread over at least `days` days.
public struct AutoPromotion: Hashable, Sendable {
  public var lookups: Int
  public var days: Int

  public init(lookups: Int, days: Int) {
    self.lookups = lookups
    self.days = days
  }

  /// Architecture 8.3: three lookups on at least two different days.
  public static let standard = AutoPromotion(lookups: 3, days: 2)
}

/// The fixed review ladder of architecture 8.5, in days.
public let reviewIntervals = [1, 2, 4, 7, 15, 30, 60]

public enum VocabError: Error, Equatable, Sendable {
  /// The file was written by a newer version of the app; it is left untouched.
  case newerSchema(Int)
  /// A lookup whose lemma normalizes to nothing.
  case emptyLemma
  case noSuchTerm(Int64)
  /// A review of a term that is not 要学.
  case notLearning(Int64)
  case sqlite(code: Int32, message: String)
}
