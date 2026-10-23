// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The fields this tool reads from one wiktextract JSONL line (one word, one part of speech).
/// Both Wiktionary editions use this shape. Everything else in the line (examples,
/// categories, audio, etymology) is skipped.
public struct WiktionaryEntry: Sendable, Equatable, Decodable {
  public var word: String
  public var langCode: String
  public var pos: String
  public var forms: [Form]?
  public var sounds: [Sound]?
  public var senses: [WiktionarySense]?
  /// Translation tables the extraction could not attach to one sense (English edition).
  public var translations: [Translation]?

  enum CodingKeys: String, CodingKey {
    case word, pos, forms, sounds, senses, translations
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
    /// Translations kaikki.org's post-processing attached to this sense (English edition).
    /// The attachment is a guess and often wrong, so the builder ignores which sense holds
    /// them and regroups them by their table's `sense` text.
    public var translations: [Translation]?

    enum CodingKeys: String, CodingKey {
      case glosses, tags, translations
      case formOf = "form_of"
      case altOf = "alt_of"
    }
  }

  public struct Target: Sendable, Equatable, Decodable {
    public var word: String
  }

  /// One row of an English Wiktionary translation table: the word in one language, and the
  /// table's sense hint ("institution", "edge of river or lake"), shared by every row of
  /// the table.
  public struct Translation: Sendable, Equatable, Decodable {
    public var lang: String?
    public var langCode: String?
    public var word: String?
    public var sense: String?
    public var tags: [String]?

    public init(
      lang: String?, langCode: String?, word: String?, sense: String?, tags: [String]? = nil
    ) {
      self.lang = lang
      self.langCode = langCode
      self.word = word
      self.sense = sense
      self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
      case lang, word, sense, tags
      case langCode = "lang_code"
    }
  }
}

/// Calls `body` with each non-empty line of a file, reading it in fixed-size chunks so a
/// multi-gigabyte JSONL file never has to fit in memory. A `.gz` file is decompressed on the
/// fly by the system `gzip`, so it is never expanded on disk.
public func forEachLine(of url: URL, _ body: (Data) throws -> Void) throws {
  guard url.pathExtension == "gz" else {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    try forEachLine(of: handle, body)
    return
  }
  let gzip = Process()
  gzip.executableURL = URL(filePath: "/usr/bin/gzip")
  gzip.arguments = ["-dc", url.path]
  let pipe = Pipe()
  gzip.standardOutput = pipe
  try gzip.run()
  do {
    try forEachLine(of: pipe.fileHandleForReading, body)
  } catch {
    gzip.terminate()
    gzip.waitUntilExit()
    throw error
  }
  gzip.waitUntilExit()
  guard gzip.terminationStatus == 0 else {
    throw BuildError("gzip exited with \(gzip.terminationStatus) for \(url.path)")
  }
}

/// Reads with plain `read(2)` into one reused buffer: `FileHandle.read` hands out a new
/// autoreleased object per chunk, which kept hundreds of megabytes alive on a gigabyte pipe.
private func forEachLine(of handle: FileHandle, _ body: (Data) throws -> Void) throws {
  var buffer = [UInt8](repeating: 0, count: 1 << 20)
  var pending: [UInt8] = []
  func emit(_ line: Data) throws {
    // Foundation decoding autoreleases; drain per line or memory grows with the file.
    if !line.isEmpty { try autoreleasepool { try body(line) } }
  }
  while true {
    let count = buffer.withUnsafeMutableBytes {
      read(handle.fileDescriptor, $0.baseAddress, $0.count)
    }
    if count < 0 && errno == EINTR { continue }
    guard count >= 0 else { throw BuildError("read failed with errno \(errno)") }
    if count == 0 { break }
    var start = 0
    while let newline = buffer[start..<count].firstIndex(of: 0x0A) {
      if pending.isEmpty {
        try emit(Data(buffer[start..<newline]))
      } else {
        pending += buffer[start..<newline]
        try emit(Data(pending))
        pending.removeAll(keepingCapacity: true)
      }
      start = newline + 1
    }
    pending += buffer[start..<count]
  }
  try emit(Data(pending))
}
