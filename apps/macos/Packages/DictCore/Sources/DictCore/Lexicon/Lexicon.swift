// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import NaturalLanguage
import SQLite3

/// Raised when the dictionary database cannot be opened or is not one.
public struct LexiconError: Error, Equatable, CustomStringConvertible {
  public var description: String
}

/// The instant dictionary layer over `dict-en-zh.sqlite` (architecture 7.3–7.4): one
/// read-only connection per actor, with its statements prepared once.
public actor Lexicon {
  // Immutable after init and used only on the actor; deinit has exclusive access.
  nonisolated(unsafe) private let db: OpaquePointer
  nonisolated(unsafe) private let headwords: OpaquePointer
  nonisolated(unsafe) private let senses: OpaquePointer
  private let dataSources: [DataSource]
  private let tagger = NLTagger(tagSchemes: [.lemma])

  /// Opens the database at `url` read-only. Throws when the file is missing, is not sqlite,
  /// or lacks the tables of schema 2.
  public init(url: URL) throws {
    var handle: OpaquePointer?
    let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
    guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
      sqlite3_close(handle)
      throw LexiconError(description: "cannot open \(url.path): \(message)")
    }
    // sqlite reads the file lazily, so preparing the statements is what checks it.
    var prepared: [OpaquePointer] = []
    do {
      for sql in [Self.lookupSQL, Self.sensesSQL] {
        prepared.append(try Self.prepare(sql, on: handle))
      }
      dataSources = Self.readSources(try Self.prepare(Self.sourcesSQL, on: handle))
    } catch {
      prepared.forEach { sqlite3_finalize($0) }
      sqlite3_close(handle)
      throw LexiconError(description: "\(url.path) is not a dictionary database: \(error)")
    }
    db = handle
    headwords = prepared[0]
    senses = prepared[1]
  }

  deinit {
    sqlite3_finalize(headwords)
    sqlite3_finalize(senses)
    sqlite3_close(db)
  }

  /// The headwords for a selected term in display order, or none (architecture 7.4): the
  /// term's own headword and every lemma it is a form of; when there are none, the lemma
  /// `NLTagger` gives, read in `context` (the sentence the term was found in) when it has one.
  public func lookup(_ term: String, context: String?) -> [LexiconEntry] {
    let surface = term.trimmingCharacters(in: Self.edgeTrim)
    let key = normalizedKey(surface)
    guard !key.isEmpty else { return [] }
    let direct = entries(forKey: key)
    guard direct.isEmpty else { return direct }
    let lemmaKey = normalizedKey(
      lemma(of: surface, in: context).trimmingCharacters(in: Self.edgeTrim))
    guard !lemmaKey.isEmpty, lemmaKey != key else { return [] }
    return entries(forKey: lemmaKey)
  }

  /// The inputs the database was built from, from its `meta` table.
  public func sources() -> [DataSource] { dataSources }

  // MARK: - Queries

  /// build-dict's `lookupSQL` (`tools/build-dict/Sources/DictBuild/Stats.swift`) with the
  /// columns an entry needs; the WHERE and ORDER BY must stay the same as there.
  static let lookupSQL = """
    SELECT h.id, h.lemma, h.ipa_us, h.ipa_uk, h.zipf FROM headword h
    WHERE h.lemma_key = ?1 OR h.id IN (SELECT headword_id FROM form WHERE form_key = ?1)
    ORDER BY
      h.lemma_key = ?1
        AND NOT EXISTS (SELECT 1 FROM sense WHERE headword_id = h.id AND source = 'en'),
      h.zipf IS NULL, h.zipf DESC, h.lemma_key = ?1, h.lemma_key
    """
  static let sensesSQL =
    "SELECT pos, gloss, hint, source FROM sense WHERE headword_id = ? ORDER BY ord"
  static let sourcesSQL = "SELECT value FROM meta WHERE key = 'sources'"

  /// Leading and trailing whitespace and punctuation, never part of a key: “run,” → run.
  /// Symbols stay, so C++ keeps its pluses.
  static let edgeTrim = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)

  private func entries(forKey key: String) -> [LexiconEntry] {
    defer { sqlite3_reset(headwords) }
    sqlite3_bind_text(headwords, 1, key, -1, sqliteTransient)
    var entries: [LexiconEntry] = []
    while sqlite3_step(headwords) == SQLITE_ROW {
      let zipf =
        sqlite3_column_type(headwords, 4) == SQLITE_NULL
        ? nil : sqlite3_column_double(headwords, 4)
      entries.append(
        LexiconEntry(
          lemma: Self.text(headwords, 1) ?? "", ipaUS: Self.text(headwords, 2),
          ipaUK: Self.text(headwords, 3), band: FrequencyBand(zipf: zipf),
          senses: senses(of: sqlite3_column_int64(headwords, 0))))
    }
    return entries
  }

  private func senses(of headword: Int64) -> [LexiconSense] {
    defer { sqlite3_reset(senses) }
    sqlite3_bind_int64(senses, 1, headword)
    var result: [LexiconSense] = []
    while sqlite3_step(senses) == SQLITE_ROW {
      result.append(
        LexiconSense(
          pos: Self.text(senses, 0) ?? "", gloss: Self.text(senses, 1) ?? "",
          hint: Self.text(senses, 2), source: Self.text(senses, 3) ?? ""))
    }
    return result
  }

  /// `NLTagger`'s lemma of each word of `term`, joined by spaces (took off → take off). The
  /// words are tagged inside `context` when it contains the term as whole words, since the
  /// sentence decides between lemmas (the leaves fell → leaf, he leaves → leave).
  private func lemma(of term: String, in context: String?) -> String {
    let (text, range) =
      context.flatMap { context in
        Self.wholeWordRange(of: term, in: context).map { (context, $0) }
      } ?? (term, term.startIndex..<term.endIndex)
    tagger.string = text
    tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
    var words: [String] = []
    tagger.enumerateTags(
      in: range, unit: .word, scheme: .lemma, options: [.omitWhitespace, .omitPunctuation]
    ) { tag, wordRange in
      words.append(tag?.rawValue ?? String(text[wordRange]))
      return true
    }
    return words.joined(separator: " ")
  }

  /// The first case-insensitive occurrence of `term` in `text` not inside a longer word.
  static func wholeWordRange(of term: String, in text: String) -> Range<String.Index>? {
    var searchStart = text.startIndex
    while let range = text.range(
      of: term, options: [.caseInsensitive], range: searchStart..<text.endIndex)
    {
      let before =
        range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
      let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
      if before?.isLetter != true, after?.isLetter != true { return range }
      searchStart = text.index(after: range.lowerBound)
    }
    return nil
  }

  // MARK: - sqlite

  private static func prepare(_ sql: String, on db: OpaquePointer) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw LexiconError(description: String(cString: sqlite3_errmsg(db)))
    }
    return statement
  }

  /// `meta.sources` decoded; none when the row is missing or malformed, which should not stop
  /// lookups.
  private static func readSources(_ statement: OpaquePointer) -> [DataSource] {
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let json = text(statement, 0) else { return [] }
    return (try? JSONDecoder().decode([DataSource].self, from: Data(json.utf8))) ?? []
  }

  private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
    sqlite3_column_text(statement, column).map { String(cString: $0) }
  }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
