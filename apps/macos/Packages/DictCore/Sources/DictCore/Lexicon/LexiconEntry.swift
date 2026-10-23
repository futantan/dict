// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How common a word is, cut from its Zipf value (architecture 7.4). The thresholds are the
/// same as the dictionary builder's `FrequencyBand`.
public enum FrequencyBand: Sendable, Equatable {
  case common, moderate, rare

  /// common: Zipf ≥ 4.5; moderate: 3.5 ≤ Zipf < 4.5; rare: below 3.5 or no frequency.
  public init(zipf: Double?) {
    switch zipf ?? 0 {
    case 4.5...: self = .common
    case 3.5..<4.5: self = .moderate
    default: self = .rare
    }
  }
}

/// One short Simplified Chinese definition, in display order.
public struct LexiconSense: Sendable, Equatable {
  /// The model card's part-of-speech enum, or "" when the source has none.
  public var pos: String
  public var gloss: String
  /// The English sense hint of a translation table, for example "institution".
  public var hint: String?
  /// "zh" or "en": which Wiktionary edition the gloss comes from, for the attribution link.
  public var source: String

  public init(pos: String, gloss: String, hint: String? = nil, source: String) {
    self.pos = pos
    self.gloss = gloss
    self.hint = hint
    self.source = source
  }
}

/// One headword with all its senses.
public struct LexiconEntry: Sendable, Equatable {
  public var lemma: String
  public var ipaUS: String?
  public var ipaUK: String?
  public var band: FrequencyBand?
  public var senses: [LexiconSense]

  public init(
    lemma: String, ipaUS: String? = nil, ipaUK: String? = nil, band: FrequencyBand? = nil,
    senses: [LexiconSense]
  ) {
    self.lemma = lemma
    self.ipaUS = ipaUS
    self.ipaUK = ipaUK
    self.band = band
    self.senses = senses
  }
}

/// One input of the dictionary database, as the builder records it in `meta.sources`, for the
/// acknowledgements page.
public struct DataSource: Sendable, Equatable, Codable {
  public var name: String
  public var url: String
  public var snapshotDate: String
  public var sha256: String
  public var license: String
  public var licenseURL: String

  public init(
    name: String, url: String, snapshotDate: String, sha256: String, license: String,
    licenseURL: String
  ) {
    self.name = name
    self.url = url
    self.snapshotDate = snapshotDate
    self.sha256 = sha256
    self.license = license
    self.licenseURL = licenseURL
  }
}
