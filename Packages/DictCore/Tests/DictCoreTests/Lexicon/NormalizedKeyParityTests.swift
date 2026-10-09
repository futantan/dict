// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

/// The dictionary's `lemma_key` and `form_key` columns are written by build-dict's own
/// `normalizedKey` (`tools/build-dict/Sources/DictBuild/Text.swift`); the app looks them up with
/// DictCore's. The two packages cannot depend on each other, so this keeps a copy of the
/// builder's implementation and checks both give the same key on a shared word list.
struct NormalizedKeyParityTests {
  /// Verbatim copy of build-dict's `normalizedKey`. Update it together with the original.
  private static func buildDictNormalizedKey(_ text: String) -> String {
    text.precomposedStringWithCompatibilityMapping
      .lowercased()
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  static let words = [
    "run", "Run", "RUN", "Café", "Cafe\u{0301}", "CAFÉ", "naïve", "Naı\u{0308}ve", "résumé",
    "state-of-the-art", "STATE-OF-THE-ART", "e-mail", "don't", "Don’t", "o'clock", "rock 'n' roll",
    "take off", "  take   off ", "take\u{00A0}off", "take\u{3000}off", "look\t\nup",
    "Ｈｅｌｌｏ", "ﬁle", "Straße", "İstanbul", "Ångström", "Å", "œuvre", "Æsir",
    "x²", "½", "™", "St.", "U.S.A.", "C++", "", "   ",
  ]

  @Test(arguments: words)
  func matchesBuildDict(word: String) {
    #expect(normalizedKey(word) == Self.buildDictNormalizedKey(word))
  }
}
