// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The two accents the dictionary stores (architecture 7.1).
public enum Accent: Sendable, Hashable { case uk, us }

/// Which of the stored accents a Wiktionary pronunciation is labelled with. Labels come both as
/// normalized `tags` and as free-text `raw_tags` in either script, and they can disagree
/// (`run` has `tags: ["US"]` with `raw_tags: ["英國"]`), so every label counts.
/// Regional labels such as Australia or 北英格蘭 match neither accent.
public func accents(tags: [String], rawTags: [String]) -> Set<Accent> {
  var result: Set<Accent> = []
  for tag in tags {
    if ukTags.contains(tag) { result.insert(.uk) }
    if usTags.contains(tag) { result.insert(.us) }
  }
  for raw in rawTags {
    let label = toSimplified(raw)
    if label == "英" || label == "RP" || ukRawFragments.contains(where: label.contains) {
      result.insert(.uk)
    }
    if label == "美" || label == "GA" || label == "GAm"
      || usRawFragments.contains(where: label.contains)
    {
      result.insert(.us)
    }
  }
  return result
}

private let ukTags: Set = ["UK", "British", "Received-Pronunciation", "Southern-England"]
private let usTags: Set = ["US", "General-American"]
private let ukRawFragments = ["英国", "英式", "英音"]
private let usRawFragments = ["美国", "美式", "通用美"]

/// One pronunciation line as wiktextract extracts it.
public struct Sound: Sendable, Equatable, Decodable {
  public var ipa: String?
  public var tags: [String]?
  public var rawTags: [String]?

  public init(ipa: String?, tags: [String]? = nil, rawTags: [String]? = nil) {
    self.ipa = ipa
    self.tags = tags
    self.rawTags = rawTags
  }

  enum CodingKeys: String, CodingKey {
    case ipa, tags
    case rawTags = "raw_tags"
  }
}

/// Picks the British and American IPA from a word's pronunciation lines, in order. Only
/// phonemic transcriptions (`/…/`) are used. A line labelled with an accent wins; an unlabelled
/// line fills an accent that is still empty, since Wiktionary leaves the general form unlabelled.
public func pickIPA(_ sounds: [Sound]) -> (uk: String?, us: String?) {
  var choice = IPAChoice()
  choice.add(sounds)
  return choice.result
}

/// `pickIPA` kept as running state, so a word's pronunciation lines need not be stored until
/// the end of the build: the first labelled transcription per accent, and the first
/// unlabelled one.
struct IPAChoice: Sendable {
  var uk: String?
  var us: String?
  var unlabelled: String?

  mutating func add(_ sounds: [Sound]) {
    for sound in sounds {
      guard let ipa = sound.ipa.map(phonemic) ?? nil else { continue }
      let tags = sound.tags ?? []
      let rawTags = sound.rawTags ?? []
      if tags.isEmpty && rawTags.isEmpty {
        if unlabelled == nil { unlabelled = ipa }
        continue
      }
      let found = accents(tags: tags, rawTags: rawTags)
      if found.contains(.uk), uk == nil { uk = ipa }
      if found.contains(.us), us == nil { us = ipa }
    }
  }

  var result: (uk: String?, us: String?) { (uk ?? unlabelled, us ?? unlabelled) }

  /// The choice over `first`'s lines followed by `second`'s.
  static func + (first: IPAChoice, second: IPAChoice) -> IPAChoice {
    IPAChoice(
      uk: first.uk ?? second.uk, us: first.us ?? second.us,
      unlabelled: first.unlabelled ?? second.unlabelled)
  }
}

/// The transcription when it is a single phonemic one (`/ɹʌn/`), trimmed; nil otherwise.
private func phonemic(_ ipa: String) -> String? {
  let trimmed = ipa.trimmingCharacters(in: .whitespaces)
  guard trimmed.count > 2, trimmed.hasPrefix("/"), trimmed.hasSuffix("/"),
    trimmed.filter({ $0 == "/" }).count == 2
  else { return nil }
  return trimmed
}
