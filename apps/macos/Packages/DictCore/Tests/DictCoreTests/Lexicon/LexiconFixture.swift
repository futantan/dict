// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SQLite3

/// A few dozen rows in the dictionary builder's schema 2 (`tools/build-dict` `DatabaseWriter`),
/// written to a temporary file. Each row exists for a test in `LexiconTests`.
enum LexiconFixture {
  static let sourcesJSON = """
    [{"license":"CC BY-SA 4.0","licenseURL":"https://creativecommons.org/licenses/by-sa/4.0/",\
    "name":"Wiktionary (en)","sha256":"aa11","snapshotDate":"2026-10-02",\
    "url":"https://kaikki.org/dictionary/English/"},\
    {"license":"CC BY-SA 4.0","licenseURL":"https://creativecommons.org/licenses/by-sa/4.0/",\
    "name":"FrequencyWords","sha256":"bb22","snapshotDate":"2018-01-01",\
    "url":"https://github.com/hermitdave/FrequencyWords"}]
    """

  static let schema = """
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
      source      TEXT NOT NULL,
      hint        TEXT,
      PRIMARY KEY (headword_id, ord)
    ) WITHOUT ROWID;
    CREATE TABLE form (
      form_key    TEXT NOT NULL,
      headword_id INTEGER NOT NULL REFERENCES headword(id),
      PRIMARY KEY (form_key, headword_id)
    ) WITHOUT ROWID;
    """

  static let rows = """
    INSERT INTO meta VALUES ('schema_version', '2'), ('sources', '\(sourcesJSON)');
    INSERT INTO headword VALUES
      (1, 'run', 'run', 5.5, '/ɹʌn/', '/rʌn/', 'run'),
      (2, 'go', 'go', 6.0, '/ɡoʊ/', '/ɡəʊ/', 'go'),
      -- taken: its own entry is more frequent but has no translation table, so it goes last.
      (3, 'take', 'take', 5.8, '/teɪk/', NULL, 'take'),
      (4, 'taken', 'taken', 6.1, NULL, NULL, 'taken'),
      -- left: its own entry has a translation table, so frequency decides.
      (5, 'leave', 'leave', 5.0, '/liv/', '/liːv/', 'leave'),
      (6, 'left', 'left', 5.5, '/lɛft/', '/left/', 'left'),
      -- rose: equal frequency, the lemma goes first.
      (7, 'rise', 'rise', 4.0, NULL, NULL, 'rise'),
      (8, 'rose', 'rose', 4.0, NULL, NULL, 'rose'),
      -- leaf and leave: `leaves` is in no table, NLTagger picks one from the sentence.
      (9, 'leaf', 'leaf', 4.2, '/lif/', NULL, 'leaf'),
      (10, 'serendipity', 'serendipity', NULL, NULL, NULL, 'serendipity'),
      (11, 'state-of-the-art', 'state-of-the-art', 3.49, NULL, NULL, 'state-of-the-art'),
      (12, 'take off', 'take off', NULL, NULL, NULL, 'take off'),
      (13, 'café', 'café', 3.5, NULL, NULL, 'café');
    INSERT INTO sense VALUES
      (1, 0, 'verb', '跑、奔跑', 'en', 'move swiftly'),
      (1, 1, 'noun', '跑步', 'zh', NULL),
      (2, 0, 'verb', '去、走', 'en', NULL),
      (3, 0, 'verb', '拿、取', 'en', 'grip with the hands'),
      (4, 0, 'adjective', '迷上', 'zh', NULL),
      (5, 0, 'verb', '离开', 'en', NULL),
      (6, 0, 'adjective', '左', 'en', 'opposite of right'),
      (7, 0, 'verb', '上升', 'en', NULL),
      (8, 0, 'noun', '玫瑰', 'en', NULL),
      (9, 0, 'noun', '叶子', 'en', NULL),
      (10, 0, 'noun', '意外发现', 'zh', NULL),
      (11, 0, 'adjective', '最先进的', 'en', NULL),
      (12, 0, 'phrasal verb', '起飞', 'en', NULL),
      (13, 0, 'noun', '咖啡馆', 'en', NULL);
    INSERT INTO form VALUES
      ('ran', 1), ('runs', 1), ('went', 2), ('took', 3), ('taken', 3), ('left', 5), ('rose', 7);
    """

  /// A new database file in a fresh temporary directory.
  static func write() throws -> URL {
    let url = try temporaryDirectory().appending(path: "dict-en-zh.sqlite")
    var db: OpaquePointer?
    defer { sqlite3_close(db) }
    guard
      sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        == SQLITE_OK,
      sqlite3_exec(db, schema + rows, nil, nil, nil) == SQLITE_OK
    else { throw FixtureError(String(cString: sqlite3_errmsg(db))) }
    return url
  }

  static func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "LexiconTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  struct FixtureError: Error {
    let message: String
    init(_ message: String) { self.message = message }
  }
}
