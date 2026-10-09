// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SQLite3

/// A value bound to or read from a statement.
enum VocabValue: Equatable {
  case integer(Int64)
  case text(String)
  case null

  var int64: Int64? {
    if case .integer(let value) = self { value } else { nil }
  }

  var int: Int? { int64.map(Int.init) }

  var string: String? {
    if case .text(let value) = self { value } else { nil }
  }
}

extension Optional where Wrapped == String {
  var vocabValue: VocabValue { map(VocabValue.text) ?? .null }
}

extension Optional where Wrapped == Int {
  var vocabValue: VocabValue { map { .integer(Int64($0)) } ?? .null }
}

/// The one sqlite connection of a `VocabStore`: a thin wrapper over the C API that prepares
/// each statement when used and finalizes it right after.
final class VocabDatabase {
  private var handle: OpaquePointer?

  init(path: String) throws(VocabError) {
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    let code = sqlite3_open_v2(path, &handle, flags, nil)
    guard code == SQLITE_OK else {
      let error = VocabError.sqlite(code: code, message: Self.message(handle, code))
      sqlite3_close_v2(handle)
      handle = nil
      throw error
    }
    sqlite3_extended_result_codes(handle, 1)
    sqlite3_busy_timeout(handle, 2000)
  }

  deinit { sqlite3_close_v2(handle) }

  /// Runs one or more statements that take no parameters.
  func execute(_ sql: String) throws(VocabError) {
    let code = sqlite3_exec(handle, sql, nil, nil, nil)
    guard code == SQLITE_OK else { throw error(code) }
  }

  /// Runs a statement and returns its rows.
  @discardableResult
  func rows(_ sql: String, _ values: [VocabValue] = []) throws(VocabError) -> [[VocabValue]] {
    var statement: OpaquePointer?
    var code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
    defer { sqlite3_finalize(statement) }
    guard code == SQLITE_OK, let statement else { throw error(code) }
    for (offset, value) in values.enumerated() {
      let index = Int32(offset + 1)
      switch value {
      case .integer(let number): code = sqlite3_bind_int64(statement, index, number)
      case .text(let text): code = sqlite3_bind_text(statement, index, text, -1, transient)
      case .null: code = sqlite3_bind_null(statement, index)
      }
      guard code == SQLITE_OK else { throw error(code) }
    }
    var rows: [[VocabValue]] = []
    while true {
      code = sqlite3_step(statement)
      if code == SQLITE_DONE { return rows }
      guard code == SQLITE_ROW else { throw error(code) }
      rows.append((0..<sqlite3_column_count(statement)).map { column(statement, $0) })
    }
  }

  /// The first column of the first row.
  func scalar(_ sql: String, _ values: [VocabValue] = []) throws(VocabError) -> VocabValue {
    try rows(sql, values).first?.first ?? .null
  }

  var changes: Int { Int(sqlite3_changes(handle)) }

  /// Runs `body` in one write transaction, rolled back when it throws.
  func transaction<T>(_ body: () throws(VocabError) -> T) throws(VocabError) -> T {
    try execute("BEGIN IMMEDIATE")
    do {
      let result = try body()
      try execute("COMMIT")
      return result
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  private func column(_ statement: OpaquePointer, _ index: Int32) -> VocabValue {
    switch sqlite3_column_type(statement, index) {
    case SQLITE_INTEGER: .integer(sqlite3_column_int64(statement, index))
    case SQLITE_NULL: .null
    default: sqlite3_column_text(statement, index).map { .text(String(cString: $0)) } ?? .null
    }
  }

  private func error(_ code: Int32) -> VocabError {
    .sqlite(code: code, message: Self.message(handle, code))
  }

  private static func message(_ handle: OpaquePointer?, _ code: Int32) -> String {
    handle.map { String(cString: sqlite3_errmsg($0)) } ?? String(cString: sqlite3_errstr(code))
  }
}

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
