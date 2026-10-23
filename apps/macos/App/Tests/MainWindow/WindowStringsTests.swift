// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictApp

/// Counts in the window read right in English, singular and plural, and in Chinese.
struct WindowStringsTests {
  private func chinese(_ key: String, table: String, _ arguments: any CVarArg...) throws -> String {
    let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    let format = bundle.localizedString(forKey: key, value: "<missing>", table: table)
    return String(format: format, locale: Locale(identifier: "zh-Hans"), arguments: arguments)
  }

  @Test func theTodayUnitsFollowTheirNumber() {
    #expect(WindowStrings.lookedUpUnit(terms: 1, sentences: 1) == "word · 1 sentence")
    #expect(WindowStrings.lookedUpUnit(terms: 12, sentences: 5) == "words · 5 sentences")
    #expect(WindowStrings.lookedUpUnit(terms: 0, sentences: 0) == "words · 0 sentences")
    #expect(WindowStrings.wroteUnit(count: 1, replaced: 1) == "time · replaced 1")
    #expect(WindowStrings.wroteUnit(count: 7, replaced: 6) == "times · replaced 6")
    #expect(WindowStrings.dueUnit(1) == "word")
    #expect(WindowStrings.dueUnit(9) == "words")
  }

  @Test func aWordSeenOnceSaysSo() {
    #expect(WindowStrings.encounters(1) == "Seen once")
    #expect(WindowStrings.encounters(5) == "Seen 5 times")
  }

  @Test func theRecordCountsArePlural() {
    #expect(
      SettingsText.recordsCount(terms: 1, sentences: 1)
        == "1 word and 1 sentence, never uploaded to any server.")
    #expect(
      SettingsText.recordsCount(terms: 2, sentences: 0)
        == "2 words and 0 sentences, never uploaded to any server.")
  }

  /// Chinese has one form, so the singular strings read as the plural ones.
  @Test func theChineseUnitsHaveOneForm() throws {
    for key in ["word · %lld sentences", "words · %lld sentences"] {
      #expect(try chinese(key, table: "MainWindow", 5) == "个词 · 5 句")
    }
    for key in ["time · replaced %lld", "times · replaced %lld"] {
      #expect(try chinese(key, table: "MainWindow", 6) == "次 · 替换 6 次")
    }
    #expect(try chinese("word", table: "MainWindow") == "个词")
    #expect(try chinese("words", table: "MainWindow") == "个词")
    #expect(try chinese("Seen %lld times", table: "MainWindow", 5) == "第 5 次")
    #expect(
      try chinese("Word List · %lld words this session", table: "Review", 9) == "生词本 · 本轮 9 个词")
  }
}
