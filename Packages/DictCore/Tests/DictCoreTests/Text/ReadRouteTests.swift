// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

struct ReadRouteTests {
  @Test(arguments: [
    ("ran", ReadRoute.lookUp),
    ("look forward to", .lookUp),
    ("state-of-the-art", .lookUp),
    ("Bonjour", .lookUp),
    ("The quick brown fox jumps over the lazy dog.", .translate),
    ("你好", .translate),
    ("我想学英语", .translate),
    ("https://example.com", .nothing),
    ("2024", .nothing),
    ("  ", .nothing),
  ])
  func routesAChineseSpeakerLearningEnglish(text: String, route: ReadRoute) {
    #expect(readRoute(text, pair: LanguagePair()) == route)
  }

  @Test func myLanguageDependsOnThePair() {
    let english = LanguagePair(
      mine: Locale.Language(identifier: "en"), learning: Locale.Language(identifier: "zh-Hans"))
    #expect(readRoute("你好", pair: english) == .lookUp)
    #expect(readRoute("hello", pair: english) == .translate)
  }
}
