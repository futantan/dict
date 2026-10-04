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
    /// File name inside the cache directory.
    public var file: String
    public var snapshotDate: String
    public var bytes: Int
    public var sha256: String
    public var license: String
    public var licenseURL: String
    public var homepage: String
    /// Attribution lines for `ATTRIBUTION`, as the source asks to be credited.
    public var credit: [String]
  }

  public init(snapshotDate: String, sources: [Source]) {
    self.snapshotDate = snapshotDate
    self.sources = sources
  }

  public init(contentsOf url: URL) throws {
    self = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
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
  while let chunk = try handle.read(upToCount: 1 << 22), !chunk.isEmpty {
    hasher.update(data: chunk)
  }
  return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

/// Checks that a file has exactly the manifest's size and hash.
public func verify(_ url: URL, against source: Manifest.Source) throws {
  let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
  guard size == source.bytes else {
    throw BuildError(
      "\(source.file): \(size ?? -1) bytes, manifest says \(source.bytes); "
        + "the upstream snapshot has probably been replaced, see tools/build-dict/README.md")
  }
  let hash = try sha256(of: url)
  guard hash == source.sha256 else {
    throw BuildError("\(source.file): sha256 \(hash), manifest says \(source.sha256)")
  }
}

/// Returns the cached copy of a source, downloading it with the system `curl` when it is
/// missing. An interrupted download is resumed from its `.part` file. The result is always
/// verified against the manifest.
public func fetch(_ source: Manifest.Source, cache: URL) throws -> URL {
  let target = cache.appending(path: source.file)
  if FileManager.default.fileExists(atPath: target.path) {
    try verify(target, against: source)
    return target
  }
  try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
  let partial = cache.appending(path: source.file + ".part")
  print("downloading \(source.url) (\(source.bytes) bytes)")
  let curl = Process()
  curl.executableURL = URL(filePath: "/usr/bin/curl")
  curl.arguments = [
    "--fail", "--location", "--silent", "--show-error", "--continue-at", "-",
    "--output", partial.path, source.url,
  ]
  try curl.run()
  curl.waitUntilExit()
  guard curl.terminationStatus == 0 else {
    throw BuildError("curl exited with \(curl.terminationStatus) for \(source.url)")
  }
  try verify(partial, against: source)
  try FileManager.default.moveItem(at: partial, to: target)
  return target
}
