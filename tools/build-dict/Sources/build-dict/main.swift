// SPDX-License-Identifier: GPL-3.0-or-later

import DictBuild
import Foundation

// build-dict build   download the pinned inputs (unless cached) and generate build/dict/dict-en-zh.sqlite
// build-dict stats   coverage and lookup timing of an existing database
// build-dict lookup WORD...  what the app's lookup shows for each word (architecture 7.4)
// build-dict update  pin the current upstream files in the manifest, rebuild, and print the
//                    figures before and after for review
// Paths default to the repository layout and are resolved against the working directory.

let usage = """
  usage: build-dict build [--manifest PATH] [--blocklist PATH] [--cache DIR] [--output DIR]
         build-dict stats [--manifest PATH] [--cache DIR] [--output DIR]
         build-dict lookup [--output DIR] WORD...
         build-dict update [--manifest PATH] [--blocklist PATH] [--cache DIR] [--output DIR]
  """

func option(_ name: String, default value: String) -> URL {
  let arguments = CommandLine.arguments
  if let index = arguments.firstIndex(of: name), index + 1 < arguments.count {
    return URL(filePath: arguments[index + 1])
  }
  return URL(filePath: value)
}

let manifestURL = option("--manifest", default: "tools/build-dict/manifest.json")
let blocklistURL = option("--blocklist", default: "tools/build-dict/blocklist.txt")
let cache = option("--cache", default: "build/dict/cache")
let output = option("--output", default: "build/dict")
let database = output.appending(path: "dict-en-zh.sqlite")
let tops = [1000, 5000, 20000, 50000]

func build(_ manifest: Manifest) throws {
  let start = ContinuousClock.now
  var inputs: [String: URL] = [:]
  for source in manifest.sources { inputs[source.id] = try fetch(source, cache: cache) }
  let summary = try buildDictionary(
    manifest: manifest, inputs: inputs, blocklist: try readBlocklist(blocklistURL),
    output: output)
  summary.lines.forEach { print($0) }
  print("built \(database.path) in \(ContinuousClock.now - start)")
}

func metrics(_ manifest: Manifest) throws -> Metrics {
  let frequencies = try FrequencyTable(
    contentsOf: try fetch(try manifest.source(frequencySourceID), cache: cache))
  return try databaseMetrics(database: database, frequencies: frequencies, tops: tops)
}

do {
  let manifest = try Manifest(contentsOf: manifestURL)
  switch CommandLine.arguments.dropFirst().first {
  case "build":
    try build(manifest)
  case "stats":
    try metrics(manifest).forEach { print("\($0.name): \($0.value)") }
    try timingReport(
      database: database,
      exact: ["run", "set", "bank", "light", "charge", "serendipity", "take off", "hospital"],
      forms: ["ran", "children", "better", "went", "mice", "taken", "geese", "studies"]
    ).forEach { print($0) }
  case "lookup":
    let options = Set(["--manifest", "--blocklist", "--cache", "--output"])
    let arguments = Array(CommandLine.arguments.dropFirst(2))
    let words = arguments.indices.filter {
      !options.contains(arguments[$0]) && ($0 == 0 || !options.contains(arguments[$0 - 1]))
    }.map { arguments[$0] }
    for word in words {
      let entries = try lookup(word, database: database)
      print(word + ":" + (entries.isEmpty ? " —" : ""))
      entries.forEach { print("  \($0.lemma): \($0.glosses.joined(separator: " / "))") }
    }
  case "update":
    // The figures of the database built from the current manifest, if there is one.
    let before =
      FileManager.default.fileExists(atPath: database.path) ? (try? metrics(manifest)) ?? [] : []
    let updated = try updatedManifest(manifest, cache: cache)
    guard updated != manifest else {
      print("upstream unchanged; \(manifestURL.path) left as it is")
      break
    }
    try updated.write(to: manifestURL)
    try build(updated)
    print("\nbefore (\(manifest.snapshotDate)) → after (\(updated.snapshotDate)):")
    comparisonLines(before: before, after: try metrics(updated)).forEach { print("  \($0)") }
    print(
      """

      \(manifestURL.path) now pins the files above. Review the figures and spot-check a few
      words, then commit the manifest. The old inputs stay in \(cache.path) under their hashes.
      """)
  default:
    print(usage)
    exit(2)
  }
} catch {
  FileHandle.standardError.write(Data("build-dict: \(error)\n".utf8))
  exit(1)
}
