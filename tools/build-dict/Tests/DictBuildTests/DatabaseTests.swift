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
      source(id: frequencySourceID, file: "frequency.txt"),
    ])

  static func build(into output: URL) throws -> BuildSummary {
    let inputs = Dictionary(
      uniqueKeysWithValues: manifest.sources.map {
        ($0.id, BuildTests.fixtures.appending(path: $0.file))
      })
    return try buildDictionary(manifest: manifest, inputs: inputs, blocklist: [], output: output)
  }

  static func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "build-dict-\(UUID())")
  }

  @Test func writesTheSchemaOfArchitectureSection7() throws {
    let output = Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: output) }
    let summary = try Self.build(into: output)
    #expect(summary.headwords == 16)
    #expect(summary.forms == 8)

    let db = try SQLiteConnection(
      path: output.appending(path: "dict-en-zh.sqlite").path, readOnly: true)
    let tables = try db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
      .rows().compactMap { $0[0] }
    #expect(tables == ["form", "headword", "meta", "sense"])

    let ran = try db.prepare(
      """
      SELECT h.lemma, s.pos, s.gloss FROM form f JOIN headword h ON h.id = f.headword_id
      JOIN sense s ON s.headword_id = h.id WHERE f.form_key = ? ORDER BY s.ord
      """
    ).rows([.text("ran")])
    #expect(ran.first == ["run", "verb", "奔跑"])
    #expect(ran.count == 4)

    let hospital = try db.prepare(
      "SELECT lemma, zipf, ipa_us, ipa_uk, wiki_title FROM headword WHERE lemma_key = ?"
    ).rows([.text("hospital")])
    #expect(hospital == [["hospital", "6.4", "/ˈhɑs.pɪ.tl̩/", "/ˈhɒs.pɪ.tl̩/", "hospital"]])

    let meta = Dictionary(
      uniqueKeysWithValues: try db.prepare("SELECT key, value FROM meta").rows().map {
        ($0[0] ?? "", $0[1] ?? "")
      })
    #expect(meta["schema_version"] == "1")
    #expect(meta["built_at"] == "2026-01-02")
    #expect(meta["tool_version"] == toolVersion)
    #expect(meta["license"] == "CC BY-SA 4.0")
    #expect(meta["sources"]?.contains("\"url\":\"https://example.org/en-hant.jsonl\"") == true)
    #expect(meta["attribution"]?.contains("Fixture authors") == true)

    let license = try String(contentsOf: output.appending(path: "LICENSE"), encoding: .utf8)
    #expect(license.contains("https://creativecommons.org/licenses/by-sa/4.0/"))
    let attribution = try String(contentsOf: output.appending(path: "ATTRIBUTION"), encoding: .utf8)
    #expect(attribution.contains("Fixture zhwiktionary-en-hant"))
    #expect(attribution.contains("Traditional-Simplified"))
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

  @Test func verifiesDownloadsAgainstTheManifest() throws {
    let url = BuildTests.fixtures.appending(path: "frequency.txt")
    var source = Self.source(id: frequencySourceID, file: "frequency.txt")
    source.bytes = try #require(
      try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
    source.sha256 = try sha256(of: url)
    try verify(url, against: source)

    var wrongHash = source
    wrongHash.sha256 = String(repeating: "0", count: 64)
    #expect(throws: BuildError.self) { try verify(url, against: wrongHash) }
    var wrongSize = source
    wrongSize.bytes += 1
    #expect(throws: BuildError.self) { try verify(url, against: wrongSize) }
  }

  @Test func readsTheRepositoryManifestAndBlocklist() throws {
    let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let manifest = try Manifest(contentsOf: root.appending(path: "manifest.json"))
    #expect(manifest.sources.filter { $0.id.hasPrefix(wiktionaryPrefix) }.count == 2)
    #expect(try manifest.source(frequencySourceID).license == "CC BY-SA 4.0")
    #expect(manifest.sources.allSatisfy { $0.sha256.count == 64 && $0.bytes > 0 })
    #expect(try readBlocklist(root.appending(path: "blocklist.txt")).isEmpty)
  }
}
