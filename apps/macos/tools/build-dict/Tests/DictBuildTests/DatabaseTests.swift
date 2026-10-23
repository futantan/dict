// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictBuild

struct DatabaseTests {
  static func source(id: String, file: String) -> Manifest.Source {
    Manifest.Source(
      id: id, name: "Fixture \(id)", url: "https://example.org/\(file)", file: file,
      snapshotDate: "2026-01-02", bytes: 0, sha256: "", license: "CC BY-SA 4.0",
      licenseURL: "https://creativecommons.org/licenses/by-sa/4.0/",
      homepage: "https://example.org/", credit: ["Fixture authors"])
  }

  static let manifest = Manifest(
    snapshotDate: "2026-01-02",
    sources: [
      source(id: "zhwiktionary-en-hant", file: "en-hant.jsonl"),
      source(id: "zhwiktionary-en-hans", file: "en-hans.jsonl"),
      source(id: "enwiktionary-en", file: "en-en.jsonl.gz"),
      source(id: frequencySourceID, file: "frequency.txt"),
    ])

  /// Builds from the fixtures; the English edition goes in gzipped, as it is downloaded.
  static func build(into output: URL) throws -> BuildSummary {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let gzipped = output.appending(path: "en-en.jsonl.gz")
    FileManager.default.createFile(atPath: gzipped.path, contents: nil)
    let gzip = Process()
    gzip.executableURL = URL(filePath: "/usr/bin/gzip")
    gzip.arguments = ["-nc", BuildTests.fixtures.appending(path: "en-en.jsonl").path]
    gzip.standardOutput = try FileHandle(forWritingTo: gzipped)
    try gzip.run()
    gzip.waitUntilExit()
    var inputs = Dictionary(
      uniqueKeysWithValues: manifest.sources.map {
        ($0.id, BuildTests.fixtures.appending(path: $0.file))
      })
    inputs["enwiktionary-en"] = gzipped
    return try buildDictionary(manifest: manifest, inputs: inputs, blocklist: [], output: output)
  }

  static func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "build-dict-\(UUID())")
  }

  @Test func writesTheSchemaOfArchitectureSection7() throws {
    let output = Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: output) }
    let summary = try Self.build(into: output)
    #expect(summary.headwords == 31)
    #expect(summary.sensesBySource == [.zh: 23, .en: 21])
    #expect(summary.forms == 22)

    let db = try SQLiteConnection(
      path: output.appending(path: "dict-en-zh.sqlite").path, readOnly: true)
    let tables = try db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
      .rows().compactMap { $0[0] }
    #expect(tables == ["form", "headword", "meta", "sense"])

    let ran = try db.prepare(
      """
      SELECT h.lemma, s.pos, s.gloss, s.source, s.hint FROM form f
      JOIN headword h ON h.id = f.headword_id JOIN sense s ON s.headword_id = h.id
      WHERE f.form_key = ? ORDER BY s.ord
      """
    ).rows([.text("ran")])
    #expect(
      ran == [
        ["run", "verb", "跑、奔跑", "en", "to move quickly on two feet"],
        ["run", "verb", "经营；管理", "zh", nil], ["run", "noun", "跑步", "zh", nil],
      ])

    let hospital = try db.prepare(
      "SELECT lemma, zipf, ipa_us, ipa_uk, wiki_title FROM headword WHERE lemma_key = ?"
    ).rows([.text("hospital")])
    #expect(hospital == [["hospital", "6.4", "/ˈhɑs.pɪ.tl̩/", "/ˈhɒs.pɪ.tl̩/", "hospital"]])

    let meta = Dictionary(
      uniqueKeysWithValues: try db.prepare("SELECT key, value FROM meta").rows().map {
        ($0[0] ?? "", $0[1] ?? "")
      })
    #expect(meta["schema_version"] == "2")
    #expect(meta["built_at"] == "2026-01-02")
    #expect(meta["tool_version"] == toolVersion)
    #expect(meta["license"] == "CC BY-SA 4.0")
    #expect(meta["sources"]?.contains("\"url\":\"https://example.org/en-hant.jsonl\"") == true)
    #expect(meta["attribution"]?.contains("Fixture authors") == true)

    let license = try String(contentsOf: output.appending(path: "LICENSE"), encoding: .utf8)
    #expect(license.contains("https://creativecommons.org/licenses/by-sa/4.0/"))
    #expect(license.contains("- Fixture enwiktionary-en (CC BY-SA 4.0)"))
    let attribution = try String(contentsOf: output.appending(path: "ATTRIBUTION"), encoding: .utf8)
    #expect(attribution.contains("Fixture zhwiktionary-en-hant"))
    #expect(attribution.contains("Traditional-Simplified"))
    #expect(attribution.contains("Fixture enwiktionary-en"))
    #expect(attribution.contains("https://<source>.wiktionary.org/wiki/<wiki_title>"))
  }

  @Test func looksUpOwnEntriesAndLemmasInTheOrderOfSection7() throws {
    let output = Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: output) }
    _ = try Self.build(into: output)
    let database = output.appending(path: "dict-en-zh.sqlite")
    func lemmas(_ term: String) throws -> [String] {
      try lookup(term, database: database).map(\.lemma)
    }
    #expect(try lemmas("went") == ["go"])
    #expect(try lemmas("ran") == ["run"])
    // Without frequencies the lemma goes first.
    #expect(try lemmas("worse") == ["bad", "worse"])
    #expect(try lemmas("better") == ["good", "better"])
    #expect(try lemmas("Hospital") == ["hospital"])
    #expect(try lookup("run", database: database, senses: 2).first?.glosses == ["跑、奔跑", "经营；管理"])
    #expect(try lemmas("serendipity").isEmpty)
  }

  @Test func rebuildingGivesIdenticalBytes() throws {
    let first = Self.temporaryDirectory()
    let second = Self.temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: first)
      try? FileManager.default.removeItem(at: second)
    }
    _ = try Self.build(into: first)
    _ = try Self.build(into: second)
    for file in ["dict-en-zh.sqlite", "LICENSE", "ATTRIBUTION"] {
      #expect(
        try sha256(of: first.appending(path: file)) == sha256(of: second.appending(path: file)),
        "\(file) differs between builds")
    }
  }

  @Test func readsTheRepositoryManifestAndBlocklist() throws {
    let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let manifest = try Manifest(contentsOf: root.appending(path: "manifest.json"))
    #expect(manifest.sources.compactMap { edition(ofSource: $0.id) } == [.zh, .zh, .en])
    #expect(try manifest.source(frequencySourceID).license == "CC BY-SA 4.0")
    #expect(manifest.sources.allSatisfy { $0.sha256.count == 64 && $0.bytes > 0 })
    #expect(try readBlocklist(root.appending(path: "blocklist.txt")).contains("go\t围旗"))
  }
}
