// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// The pinned inputs of a build (`tools/build-dict/manifest.json`): where each file comes
/// from, its snapshot date, exact size and SHA-256, and how it is licensed and credited.
public struct Manifest: Sendable, Equatable, Codable {
  /// The dictionary's version date: the newest snapshot among the inputs. It is written to
  /// `meta.built_at` instead of the wall clock so rebuilding gives identical bytes.
  public var snapshotDate: String
  public var sources: [Source]

  public struct Source: Sendable, Equatable, Codable {
    /// Stable identifier the builder uses to find a role's file, e.g. `zhwiktionary-en-hant`.
    public var id: String
    public var name: String
    public var url: String
    /// File name; the cached copy is `<sha256>-<file>` inside the cache directory.
    public var file: String
    /// The upstream file's date (HTTP Last-Modified when it was pinned).
    public var snapshotDate: String
    public var bytes: Int
    public var sha256: String
    public var license: String
    public var licenseURL: String
    public var homepage: String
    /// Attribution lines for `ATTRIBUTION`, as the source asks to be credited.
    public var credit: [String]
    /// A page stating which dump and tool versions produced the file (kaikki.org), read by
    /// `build-dict update` to refresh `extraction`.
    public var infoPage: String?
    /// One line on how the file was produced, e.g. "Extracted on … from the … dump dated …".
    public var extraction: String?
  }

  public init(snapshotDate: String, sources: [Source]) {
    self.snapshotDate = snapshotDate
    self.sources = sources
  }

  public init(contentsOf url: URL) throws {
    self = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
  }

  /// Writes the manifest as pretty-printed JSON with sorted keys, so updates diff cleanly.
  public func write(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(self)
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
  }

  public func source(_ id: String) throws -> Source {
    guard let source = sources.first(where: { $0.id == id }) else {
      throw BuildError("manifest has no source \(id)")
    }
    return source
  }
}

public struct BuildError: Error, CustomStringConvertible {
  public let description: String
  public init(_ description: String) { self.description = description }
}

/// SHA-256 of a file as lowercase hex, read in chunks.
public func sha256(of url: URL) throws -> String {
  let handle = try FileHandle(forReadingFrom: url)
  defer { try? handle.close() }
  var hasher = SHA256()
  // Each chunk is autoreleased; without a pool per read the whole file stays in memory.
  while try autoreleasepool(invoking: {
    guard let chunk = try handle.read(upToCount: 1 << 22), !chunk.isEmpty else { return false }
    hasher.update(data: chunk)
    return true
  }) {}
  return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

func fileSize(_ url: URL) throws -> Int {
  try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? -1
}

/// Checks that a file has exactly the manifest's size and hash.
public func verify(_ url: URL, against source: Manifest.Source) throws {
  let size = try fileSize(url)
  guard size == source.bytes else {
    throw BuildError("\(url.path): \(size) bytes, manifest says \(source.bytes)")
  }
  let hash = try sha256(of: url)
  guard hash == source.sha256 else {
    throw BuildError("\(url.path): sha256 \(hash), manifest says \(source.sha256)")
  }
}

/// Where a source's verified copy lives: named by its hash, so copies of different snapshots
/// sit side by side and an old build stays reproducible for as long as its files are cached.
public func cachedFile(_ source: Manifest.Source, cache: URL) -> URL {
  cache.appending(path: "\(source.sha256)-\(source.file)")
}

/// Returns the cached copy of a source, downloading it with the system `curl` when it is
/// missing. A download that does not match the manifest is kept in the cache under its own
/// hash (for `build-dict update` to reuse) and reported with what to do next.
public func fetch(_ source: Manifest.Source, cache: URL) throws -> URL {
  let target = cachedFile(source, cache: cache)
  if FileManager.default.fileExists(atPath: target.path) {
    do {
      try verify(target, against: source)
    } catch {
      throw BuildError("the cached copy is damaged, delete it and run again: \(error)")
    }
    return target
  }
  print("downloading \(source.url) (\(source.bytes) bytes)")
  let download = try downloadToCache(source, cache: cache)
  guard download.bytes == source.bytes, download.sha256 == source.sha256 else {
    throw BuildError(
      """
      \(source.id): the file at \(source.url) is no longer the pinned snapshot.
        pinned:     \(source.snapshotDate), \(source.bytes) bytes, sha256 \(source.sha256)
        downloaded: \(download.date), \(download.bytes) bytes, sha256 \(download.sha256)
                    (kept as \(download.url.path))
      kaikki.org replaces its extractions at the same address about once a week and keeps no \
      old versions, so the pinned inputs can no longer be downloaded. Either:
        - run `make dict-update` to pin the current upstream files. It rebuilds and prints the \
      coverage before and after; review it, then commit tools/build-dict/manifest.json.
        - or, to reproduce the pinned build, put a copy of the old file at \(target.path) \
      (any copy with that sha256 works).
      """)
  }
  return target
}

/// A downloaded file, already moved to its hash-named place in the cache.
struct Download {
  var url: URL
  var bytes: Int
  var sha256: String
  /// The server's Last-Modified date (curl `--remote-time`), as yyyy-MM-dd in UTC.
  var date: String
}

/// Downloads a source's URL into the cache and names the file by its hash.
func downloadToCache(_ source: Manifest.Source, cache: URL) throws -> Download {
  try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
  let partial = cache.appending(path: source.file + ".part")
  try? FileManager.default.removeItem(at: partial)
  _ = try curl(["--remote-time", "--output", partial.path, source.url])
  let hash = try sha256(of: partial)
  let modified =
    try FileManager.default.attributesOfItem(atPath: partial.path)[.modificationDate] as? Date
  let named = cache.appending(path: "\(hash)-\(source.file)")
  try? FileManager.default.removeItem(at: named)
  try FileManager.default.moveItem(at: partial, to: named)
  return Download(
    url: named, bytes: try fileSize(named), sha256: hash,
    date: (modified ?? Date()).formatted(.iso8601.year().month().day()))
}

/// Runs the system curl and returns what it wrote to standard output.
func curl(_ arguments: [String]) throws -> Data {
  let process = Process()
  process.executableURL = URL(filePath: "/usr/bin/curl")
  process.arguments = ["--fail", "--location", "--silent", "--show-error"] + arguments
  let pipe = Pipe()
  process.standardOutput = pipe
  try process.run()
  let output = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw BuildError("curl exited with \(process.terminationStatus) for \(arguments.last ?? "")")
  }
  return output
}

/// Downloads every source again and returns the manifest pinned to what is upstream now:
/// new size, hash and date, and a refreshed `extraction` line where the source has an
/// `infoPage`. Sources whose file did not change keep their entry as is. The files stay in
/// the cache under their hashes, so the next build does not download them again.
public func updatedManifest(_ manifest: Manifest, cache: URL) throws -> Manifest {
  var updated = manifest
  for (index, source) in manifest.sources.enumerated() {
    print("downloading \(source.url)")
    let download = try downloadToCache(source, cache: cache)
    guard download.sha256 != source.sha256 else {
      print("  unchanged")
      continue
    }
    var next = source
    next.bytes = download.bytes
    next.sha256 = download.sha256
    next.snapshotDate = download.date
    if let page = source.infoPage {
      let html = String(decoding: try curl([page]), as: UTF8.self)
      if let line = kaikkiExtraction(html) {
        next.extraction = line
      } else {
        print("  warning: no extraction line found on \(page); `extraction` left as it was")
      }
    }
    print("  \(source.snapshotDate) → \(next.snapshotDate), \(source.bytes) → \(next.bytes) bytes")
    updated.sources[index] = next
  }
  updated.snapshotDate = updated.sources.map(\.snapshotDate).max() ?? manifest.snapshotDate
  return updated
}

/// Reads kaikki.org's standard sentence ("… extracted on 2026-09-28 from the enwiktionary dump
/// dated 2026-09-02 using wiktextract (1a05e46 and e3d6d4e).") into one attribution line.
func kaikkiExtraction(_ html: String) -> String? {
  let text = html.replacing(/<[^>]*>/, with: "")
  let pattern =
    /extracted on (\d{4}-\d{2}-\d{2}) from the (\w+) dump dated (\d{4}-\d{2}-\d{2}) using wiktextract \((\w+) and (\w+)\)/
  guard let match = text.firstMatch(of: pattern) else { return nil }
  return "Extracted on \(match.1) by kaikki.org from the \(match.2) dump dated \(match.3), "
    + "with wiktextract \(match.4) and wikitextprocessor \(match.5)."
}
