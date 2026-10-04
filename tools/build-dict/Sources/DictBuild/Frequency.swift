// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Word frequencies from a FrequencyWords list (`word count` per line, most frequent first).
/// The counts are of surface forms in subtitles, not lemmas.
public struct FrequencyTable: Sendable {
  /// Words in the list's order (most frequent first).
  public let ranked: [String]
  private let counts: [String: Int]
  private let total: Double

  /// Reads the list line by line. Words seen fewer than `minimumCount` times still count
  /// toward the corpus size but are not kept: below about Zipf 1 a value carries no signal, and
  /// the full list's long tail of one-off tokens would cost hundreds of megabytes.
  public init(contentsOf url: URL, minimumCount: Int = 3) throws {
    var ranked: [String] = []
    var counts: [String: Int] = [:]
    var total = 0
    try forEachLine(of: url) { line in
      let parts = line.split(separator: UInt8(ascii: " "))
      guard parts.count == 2, let count = Int(String(decoding: parts[1], as: UTF8.self)),
        count > 0
      else { return }
      total += count
      guard count >= minimumCount else { return }
      let word = normalizedKey(String(decoding: parts[0], as: UTF8.self))
      if counts[word] == nil { ranked.append(word) }
      counts[word, default: 0] += count
    }
    self.ranked = ranked
    self.counts = counts
    self.total = Double(max(total, 1))
  }

  /// Zipf value: log10 of occurrences per billion words, rounded to two decimals so the
  /// database does not depend on floating-point formatting. Nil for words not in the list.
  public func zipf(_ key: String) -> Double? {
    guard let count = counts[key] else { return nil }
    return (log10(Double(count) / total * 1e9) * 100).rounded() / 100
  }
}

/// The three frequency bands the panel shows (architecture 7.4), cut on the Zipf scale.
public enum FrequencyBand: String, Sendable, CaseIterable {
  case common, moderate, rare

  /// common: Zipf ≥ 4.5; moderate: 3.5 ≤ Zipf < 4.5; rare: below 3.5 or not in the list.
  public init(zipf: Double?) {
    switch zipf ?? 0 {
    case 4.5...: self = .common
    case 3.5..<4.5: self = .moderate
    default: self = .rare
    }
  }
}
