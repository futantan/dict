// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The fields this tool reads from one wiktextract JSONL line (one word, one part of speech).
/// Everything else in the line (examples, categories, audio, etymology) is skipped.
public struct WiktionaryEntry: Sendable, Equatable, Decodable {
  public var word: String
  public var langCode: String
  public var pos: String
  public var forms: [Form]?
  public var sounds: [Sound]?
  public var senses: [WiktionarySense]?

  enum CodingKeys: String, CodingKey {
    case word, pos, forms, sounds, senses
    case langCode = "lang_code"
  }

  public struct Form: Sendable, Equatable, Decodable {
    public var form: String
    public var tags: [String]?
    public var rawTags: [String]?

    enum CodingKeys: String, CodingKey {
      case form, tags
      case rawTags = "raw_tags"
    }
  }

  public struct WiktionarySense: Sendable, Equatable, Decodable {
    public var glosses: [String]?
    public var tags: [String]?
    public var formOf: [Target]?
    public var altOf: [Target]?

    enum CodingKeys: String, CodingKey {
      case glosses, tags
      case formOf = "form_of"
      case altOf = "alt_of"
    }
  }

  public struct Target: Sendable, Equatable, Decodable {
    public var word: String
  }
}

/// Calls `body` with each non-empty line of a file, reading it in fixed-size chunks so a
/// multi-gigabyte JSONL file never has to fit in memory.
public func forEachLine(of url: URL, _ body: (Data) throws -> Void) throws {
  let handle = try FileHandle(forReadingFrom: url)
  defer { try? handle.close() }
  var pending = Data()
  while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
    pending.append(chunk)
    var start = pending.startIndex
    while let newline = pending[start...].firstIndex(of: 0x0A) {
      // Foundation decoding autoreleases; drain per line or memory grows with the file.
      if newline > start { try autoreleasepool { try body(pending[start..<newline]) } }
      start = pending.index(after: newline)
    }
    pending = Data(pending[start...])
  }
  if !pending.isEmpty { try body(pending) }
}
