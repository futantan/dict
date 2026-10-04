// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Bumped whenever the output for the same inputs changes; recorded in `meta.tool_version`.
public let toolVersion = "1.0.0"

/// Manifest ids of the inputs. Every source whose id starts with `wiktionaryPrefix` is a
/// wiktextract JSONL file, read in manifest order.
public let wiktionaryPrefix = "zhwiktionary-"
public let frequencySourceID = "frequencywords-en"

public struct BuildSummary: Sendable, Equatable {
  public var headwords = 0
  public var senses = 0
  public var forms = 0
  public var withIPAUK = 0
  public var withIPAUS = 0
  public var bands: [FrequencyBand: Int] = [:]

  public var lines: [String] {
    [
      "headwords \(headwords)", "senses \(senses)", "forms \(forms)",
      "ipa_uk \(withIPAUK) (\(percent(withIPAUK, of: headwords)))",
      "ipa_us \(withIPAUS) (\(percent(withIPAUS, of: headwords)))",
    ] + FrequencyBand.allCases.map { "band \($0.rawValue) \(bands[$0, default: 0])" }
  }
}

func percent(_ part: Int, of whole: Int) -> String {
  String(format: "%.1f%%", whole == 0 ? 0 : Double(part) / Double(whole) * 100)
}

/// Builds `dict-en-zh.sqlite`, `LICENSE` and `ATTRIBUTION` into `output` from local copies of
/// the manifest's inputs (`inputs` maps source id to file). Also writes
/// `simplification-sample.tsv`, glosses before and after Traditional-Simplified conversion for
/// a human to check; it is a build by-product and is not shipped.
public func buildDictionary(
  manifest: Manifest, inputs: [String: URL], blocklist: Set<String>, output: URL
) throws -> BuildSummary {
  guard let frequencyFile = inputs[frequencySourceID] else {
    throw BuildError("missing input \(frequencySourceID)")
  }
  let frequencies = try FrequencyTable(contentsOf: frequencyFile)

  var builder = LexiconBuilder()
  var sample: [String] = []
  var changed = 0
  let decoder = JSONDecoder()
  for source in manifest.sources where source.id.hasPrefix(wiktionaryPrefix) {
    guard let file = inputs[source.id] else { throw BuildError("missing input \(source.id)") }
    try forEachLine(of: file) { line in
      let entry = try decoder.decode(WiktionaryEntry.self, from: line)
      builder.add(entry)
      for gloss in (entry.senses ?? []).flatMap({ $0.glosses ?? [] }) {
        let firstLine = String(gloss.prefix(while: { !$0.isNewline }))
        guard toSimplified(firstLine) != firstLine else { continue }
        changed += 1
        if changed % 50 == 1, sample.count < 400 {
          sample.append("\(entry.word)\t\(firstLine)\t\(toSimplified(firstLine))")
        }
      }
    }
  }

  let lexicon = builder.build(zipf: frequencies.zipf, blocklist: blocklist)
  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  let meta = [
    "schema_version": String(schemaVersion),
    "built_at": manifest.snapshotDate,
    "tool_version": toolVersion,
    "license": "CC BY-SA 4.0",
    "license_url": "https://creativecommons.org/licenses/by-sa/4.0/",
    "sources": try sourcesJSON(manifest),
    "attribution": attributionNotice(manifest),
  ]
  try writeDatabase(lexicon, meta: meta, to: output.appending(path: "dict-en-zh.sqlite"))
  try licenseNotice(manifest).write(
    to: output.appending(path: "LICENSE"), atomically: true, encoding: .utf8)
  try attributionNotice(manifest).write(
    to: output.appending(path: "ATTRIBUTION"), atomically: true, encoding: .utf8)
  try (["word\ttraditional\tsimplified"] + sample).joined(separator: "\n").appending("\n")
    .write(
      to: output.appending(path: "simplification-sample.tsv"), atomically: true, encoding: .utf8)

  var summary = BuildSummary()
  summary.headwords = lexicon.headwords.count
  summary.senses = lexicon.headwords.reduce(0) { $0 + $1.senses.count }
  summary.forms = lexicon.forms.count
  summary.withIPAUK = lexicon.headwords.count { $0.ipaUK != nil }
  summary.withIPAUS = lexicon.headwords.count { $0.ipaUS != nil }
  for headword in lexicon.headwords {
    summary.bands[FrequencyBand(zipf: headword.zipf), default: 0] += 1
  }
  return summary
}

/// Keys to leave out, one per line; `#` starts a comment.
public func readBlocklist(_ url: URL) throws -> Set<String> {
  guard FileManager.default.fileExists(atPath: url.path) else { return [] }
  let lines = try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline)
  return Set(
    lines.map { normalizedKey(String($0.prefix(while: { $0 != "#" }))) }.filter { !$0.isEmpty })
}
