// SPDX-License-Identifier: GPL-3.0-or-later

import DictBuild
import Foundation

// build-dict build   download the pinned inputs and generate build/dict/dict-en-zh.sqlite
// build-dict stats   coverage and lookup timing of an existing database
// Paths default to the repository layout and are resolved against the working directory.

let usage = """
  usage: build-dict build [--manifest PATH] [--blocklist PATH] [--cache DIR] [--output DIR]
         build-dict stats [--manifest PATH] [--cache DIR] [--output DIR]
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

do {
  let manifest = try Manifest(contentsOf: manifestURL)
  switch CommandLine.arguments.dropFirst().first {
  case "build":
    let start = ContinuousClock.now
    var inputs: [String: URL] = [:]
    for source in manifest.sources { inputs[source.id] = try fetch(source, cache: cache) }
    let summary = try buildDictionary(
      manifest: manifest, inputs: inputs, blocklist: try readBlocklist(blocklistURL),
      output: output)
    summary.lines.forEach { print($0) }
    print(
      "built \(output.appending(path: "dict-en-zh.sqlite").path) in \(ContinuousClock.now - start)")
  case "stats":
    let database = output.appending(path: "dict-en-zh.sqlite")
    let frequencies = try FrequencyTable(
      contentsOf: cache.appending(path: try manifest.source(frequencySourceID).file))
    try coverageReport(
      database: database, frequencies: frequencies, tops: [1000, 5000, 20000, 50000]
    ).forEach { print($0) }
    try timingReport(
      database: database,
      exact: ["run", "set", "bank", "light", "charge", "serendipity", "take off", "hospital"],
      forms: ["ran", "children", "better", "went", "mice", "taken", "geese", "studies"]
    ).forEach { print($0) }
  default:
    print(usage)
    exit(2)
  }
} catch {
  FileHandle.standardError.write(Data("build-dict: \(error)\n".utf8))
  exit(1)
}
