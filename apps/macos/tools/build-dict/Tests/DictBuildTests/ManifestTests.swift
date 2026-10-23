// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictBuild

/// Pinning, caching and updating inputs. "Upstream" is a local file reached through a
/// `file://` URL, which the system curl fetches like any other.
struct ManifestTests {
  /// A scratch directory with an upstream file, an info page and a cache.
  struct Upstream {
    let root = FileManager.default.temporaryDirectory.appending(path: "manifest-\(UUID())")
    var file: URL { root.appending(path: "upstream/data.jsonl") }
    var page: URL { root.appending(path: "upstream/index.html") }
    var cache: URL { root.appending(path: "cache") }

    init(contents: String) throws {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try publish(contents)
    }

    func publish(_ contents: String) throws {
      try contents.write(to: file, atomically: true, encoding: .utf8)
    }

    /// A manifest entry pinning the upstream file as it is now.
    func pinned() throws -> Manifest.Source {
      var source = DatabaseTests.source(id: "zhwiktionary-en-hant", file: "data.jsonl")
      source.url = file.absoluteString
      source.bytes = try fileSize(file)
      source.sha256 = try sha256(of: file)
      source.snapshotDate = "2026-01-02"
      source.infoPage = page.absoluteString
      source.extraction = "Extracted on 2026-01-02 by kaikki.org."
      return source
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
  }

  @Test func downloadsIntoTheCacheUnderTheHash() throws {
    let upstream = try Upstream(contents: "one\n")
    defer { upstream.remove() }
    let source = try upstream.pinned()
    let cached = try fetch(source, cache: upstream.cache)
    #expect(cached.lastPathComponent == "\(source.sha256)-data.jsonl")
    #expect(try String(contentsOf: cached, encoding: .utf8) == "one\n")

    // A second fetch uses the cache even when upstream is gone.
    try FileManager.default.removeItem(at: upstream.file)
    #expect(try fetch(source, cache: upstream.cache) == cached)
  }

  @Test func reportsAReplacedSnapshotWithWhatToDo() throws {
    let upstream = try Upstream(contents: "one\n")
    defer { upstream.remove() }
    let source = try upstream.pinned()
    try upstream.publish("two\n")
    let newHash = try sha256(of: upstream.file)

    let error = try #require(throws: BuildError.self) { try fetch(source, cache: upstream.cache) }
    #expect(error.description.contains("no longer the pinned snapshot"))
    #expect(error.description.contains(source.sha256))
    #expect(error.description.contains(newHash))
    #expect(error.description.contains("make dict-update"))
    #expect(error.description.contains(cachedFile(source, cache: upstream.cache).path))
    // The new file is kept for the update, and nothing is cached under the pinned name.
    let kept = upstream.cache.appending(path: "\(newHash)-data.jsonl")
    #expect(FileManager.default.fileExists(atPath: kept.path))
    #expect(!FileManager.default.fileExists(atPath: cachedFile(source, cache: upstream.cache).path))
  }

  @Test func refusesADamagedCachedCopy() throws {
    let upstream = try Upstream(contents: "one\n")
    defer { upstream.remove() }
    let source = try upstream.pinned()
    let cached = try fetch(source, cache: upstream.cache)
    try "On e\n".write(to: cached, atomically: true, encoding: .utf8)
    let error = try #require(throws: BuildError.self) { try fetch(source, cache: upstream.cache) }
    #expect(error.description.contains("damaged"))
  }

  @Test func updatePinsTheCurrentUpstreamFile() throws {
    let upstream = try Upstream(contents: "one\n")
    defer { upstream.remove() }
    let source = try upstream.pinned()
    let steady = upstream.root.appending(path: "upstream/frequency.txt")
    try "the 10\n".write(to: steady, atomically: true, encoding: .utf8)
    var unchanged = DatabaseTests.source(id: frequencySourceID, file: "frequency.txt")
    unchanged.url = steady.absoluteString
    unchanged.bytes = try fileSize(steady)
    unchanged.sha256 = try sha256(of: steady)
    let manifest = Manifest(snapshotDate: "2026-01-02", sources: [source, unchanged])
    try upstream.publish("two, longer\n")
    try FileManager.default.setAttributes(
      [.modificationDate: try Date("2026-09-28T18:06:52Z", strategy: .iso8601)],
      ofItemAtPath: upstream.file.path)
    try """
    <p>This dictionary is based on structured data extracted on 2026-09-28 from the
    <b>zhwiktionary</b> dump dated 2026-09-20 using wiktextract (<a>abc1234</a> and
    <a>def5678</a>).</p>
    """.replacingOccurrences(of: "\n", with: " ").write(
      to: upstream.page, atomically: true, encoding: .utf8)

    let updated = try updatedManifest(manifest, cache: upstream.cache)
    let next = updated.sources[0]
    #expect(next.bytes == 12)
    #expect(next.sha256 == (try sha256(of: upstream.file)))
    #expect(next.snapshotDate == "2026-09-28")
    #expect(
      next.extraction
        == "Extracted on 2026-09-28 by kaikki.org from the zhwiktionary dump dated 2026-09-20, "
        + "with wiktextract abc1234 and wikitextprocessor def5678.")
    #expect(updated.snapshotDate == "2026-09-28")
    #expect(FileManager.default.fileExists(atPath: cachedFile(next, cache: upstream.cache).path))
    #expect(updated.sources[1] == unchanged)

    // Updating again finds nothing new.
    #expect(try updatedManifest(updated, cache: upstream.cache) == updated)
  }

  @Test func writesTheManifestSoItReadsBackUnchanged() throws {
    let upstream = try Upstream(contents: "one\n")
    defer { upstream.remove() }
    let manifest = Manifest(snapshotDate: "2026-01-02", sources: [try upstream.pinned()])
    let url = upstream.root.appending(path: "manifest.json")
    try manifest.write(to: url)
    #expect(try Manifest(contentsOf: url) == manifest)
  }

  @Test func theRepositoryManifestIsInTheWrittenFormat() throws {
    // `build-dict update` rewrites the file; a hand edit in another format would make its
    // first diff noisy.
    let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let url = root.appending(path: "manifest.json")
    let rewritten = FileManager.default.temporaryDirectory.appending(path: "manifest-\(UUID())")
    defer { try? FileManager.default.removeItem(at: rewritten) }
    try Manifest(contentsOf: url).write(to: rewritten)
    #expect(try Data(contentsOf: rewritten) == Data(contentsOf: url))
  }

  @Test func readsTheExtractionLineOfKaikkiPages() {
    let html = """
      This dictionary is based on structured data extracted on 2026-10-02 from the zhwiktionary \
      dump dated 2026-10-01 using <a href="x">wiktextract</a> (<a href="y">1a05e46</a> and \
      <a href="z">e3d6d4e</a>).
      """
    #expect(
      kaikkiExtraction(html)
        == "Extracted on 2026-10-02 by kaikki.org from the zhwiktionary dump dated 2026-10-01, "
        + "with wiktextract 1a05e46 and wikitextprocessor e3d6d4e.")
    #expect(kaikkiExtraction("<p>nothing here</p>") == nil)
  }

  @Test func verifiesFilesAgainstTheManifest() throws {
    let url = BuildTests.fixtures.appending(path: "frequency.txt")
    var source = DatabaseTests.source(id: frequencySourceID, file: "frequency.txt")
    source.bytes = try fileSize(url)
    source.sha256 = try sha256(of: url)
    try verify(url, against: source)

    var wrongHash = source
    wrongHash.sha256 = String(repeating: "0", count: 64)
    #expect(throws: BuildError.self) { try verify(url, against: wrongHash) }
    var wrongSize = source
    wrongSize.bytes += 1
    #expect(throws: BuildError.self) { try verify(url, against: wrongSize) }
  }
}
