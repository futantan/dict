// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

struct LanguagePairTests {
  @Test func defaultsToSimplifiedChineseLearningEnglish() {
    let pair = LanguagePair()

    #expect(pair.mine.languageCode == .chinese)
    #expect(pair.mine.script == .hanSimplified)
    #expect(pair.learning.languageCode == .english)
  }

  @Test func roundTripsThroughJSON() throws {
    let pair = LanguagePair(
      mine: Locale.Language(identifier: "es"), learning: Locale.Language(identifier: "en-GB"))
    let decoded = try JSONDecoder().decode(
      LanguagePair.self, from: try JSONEncoder().encode(pair))

    #expect(decoded == pair)
  }
}
