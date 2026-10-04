// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SQLite3

/// The schema of architecture 7.3. `schema_version` in `meta` changes with it.
public let schemaVersion = 1

let schema = """
  CREATE TABLE meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
  ) WITHOUT ROWID;
  CREATE TABLE headword (
    id         INTEGER PRIMARY KEY,
    lemma      TEXT NOT NULL,
    lemma_key  TEXT NOT NULL UNIQUE,
    zipf       REAL,
    ipa_us     TEXT,
    ipa_uk     TEXT,
    wiki_title TEXT NOT NULL
  );
  CREATE TABLE sense (
    headword_id INTEGER NOT NULL REFERENCES headword(id),
    ord         INTEGER NOT NULL,
    pos         TEXT NOT NULL,
    gloss       TEXT NOT NULL,
    PRIMARY KEY (headword_id, ord)
  ) WITHOUT ROWID;
  CREATE TABLE form (
    form_key    TEXT NOT NULL,
    headword_id INTEGER NOT NULL REFERENCES headword(id),
    PRIMARY KEY (form_key, headword_id)
  ) WITHOUT ROWID;
  """

/// Writes the lexicon to a new sqlite file at `url`, replacing any existing one. Rows go in
/// in the lexicon's sorted order with ids assigned from it, no timestamps are written, and the
/// file is vacuumed, so the same input always produces the same bytes.
public func writeDatabase(_ lexicon: Lexicon, meta: [String: String], to url: URL) throws {
  let temporary = url.deletingLastPathComponent().appending(path: url.lastPathComponent + ".tmp")
  try? FileManager.default.removeItem(at: temporary)
  let db = try SQLiteConnection(path: temporary.path)
  try db.execute("PRAGMA page_size = 4096; PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF;")
  try db.execute(schema)
  try db.execute("BEGIN")

  let insertMeta = try db.prepare("INSERT INTO meta (key, value) VALUES (?, ?)")
  for (key, value) in meta.sorted(by: { $0.key < $1.key }) {
    try insertMeta.run([.text(key), .text(value)])
  }

  let insertHeadword = try db.prepare(
    "INSERT INTO headword (id, lemma, lemma_key, zipf, ipa_us, ipa_uk, wiki_title) "
      + "VALUES (?, ?, ?, ?, ?, ?, ?)")
  let insertSense = try db.prepare(
    "INSERT INTO sense (headword_id, ord, pos, gloss) VALUES (?, ?, ?, ?)")
  var ids: [String: Int] = [:]
  for (index, headword) in lexicon.headwords.enumerated() {
    let id = index + 1
    ids[headword.key] = id
    try insertHeadword.run([
      .integer(id), .text(headword.lemma), .text(headword.key),
      headword.zipf.map(Value.real) ?? .null,
      headword.ipaUS.map(Value.text) ?? .null, headword.ipaUK.map(Value.text) ?? .null,
      .text(headword.wikiTitle),
    ])
    for (ord, sense) in headword.senses.enumerated() {
      try insertSense.run([.integer(id), .integer(ord), .text(sense.pos), .text(sense.gloss)])
    }
  }

  let insertForm = try db.prepare("INSERT INTO form (form_key, headword_id) VALUES (?, ?)")
  for link in lexicon.forms {
    guard let id = ids[link.lemmaKey] else { continue }
    try insertForm.run([.text(link.formKey), .integer(id)])
  }

  try db.execute("COMMIT")
  try db.execute("VACUUM")
  db.close()
  try? FileManager.default.removeItem(at: url)
  try FileManager.default.moveItem(at: temporary, to: url)
}

enum Value {
  case integer(Int)
  case real(Double)
  case text(String)
  case null
}

/// A minimal wrapper over the sqlite3 C API, enough for a one-shot writer and the stats reader.
final class SQLiteConnection {
  private var handle: OpaquePointer?

  init(path: String, readOnly: Bool = false) throws {
    let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
    guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
      defer { sqlite3_close(handle) }
      throw BuildError("cannot open \(path): \(String(cString: sqlite3_errmsg(handle)))")
    }
  }

  deinit { close() }

  func close() {
    sqlite3_close(handle)
    handle = nil
  }

  func execute(_ sql: String) throws {
    guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
  }

  func prepare(_ sql: String) throws -> Statement {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement
    else { throw error() }
    return Statement(statement: statement, connection: self)
  }

  func error() -> BuildError { BuildError(String(cString: sqlite3_errmsg(handle))) }

  final class Statement {
    private let statement: OpaquePointer
    private let connection: SQLiteConnection

    init(statement: OpaquePointer, connection: SQLiteConnection) {
      self.statement = statement
      self.connection = connection
    }

    deinit { sqlite3_finalize(statement) }

    /// Executes a statement that returns no rows.
    func run(_ values: [Value]) throws {
      bind(values)
      defer { sqlite3_reset(statement) }
      guard sqlite3_step(statement) == SQLITE_DONE else { throw connection.error() }
    }

    /// Executes a query and returns each row's columns as text (nil for NULL).
    func rows(_ values: [Value] = []) throws -> [[String?]] {
      bind(values)
      defer { sqlite3_reset(statement) }
      var rows: [[String?]] = []
      while true {
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return rows }
        guard step == SQLITE_ROW else { throw connection.error() }
        rows.append(
          (0..<sqlite3_column_count(statement)).map { column in
            sqlite3_column_text(statement, column).map { String(cString: $0) }
          })
      }
    }

    private func bind(_ values: [Value]) {
      sqlite3_clear_bindings(statement)
      for (offset, value) in values.enumerated() {
        let index = Int32(offset + 1)
        switch value {
        case .integer(let number): sqlite3_bind_int64(statement, index, Int64(number))
        case .real(let number): sqlite3_bind_double(statement, index, number)
        case .text(let text): sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
        case .null: sqlite3_bind_null(statement, index)
        }
      }
    }
  }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
