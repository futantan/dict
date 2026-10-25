// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictApp

struct InterfaceLanguageTests {
  @Test func simplifiedChineseWhenNothingWasChosen() {
    let defaults = UserDefaults.scratch("InterfaceLanguageTests")
    #expect(InterfaceLanguage.chosen(in: defaults) == .simplifiedChinese)
  }

  @Test func englishPersists() {
    let defaults = UserDefaults.scratch("InterfaceLanguageTests")
    InterfaceLanguage.english.choose(in: defaults)
    #expect(InterfaceLanguage.chosen(in: defaults) == .english)
    InterfaceLanguage.simplifiedChinese.choose(in: defaults)
    #expect(InterfaceLanguage.chosen(in: defaults) == .simplifiedChinese)
  }

  @Test func anUnknownStoredValueFallsBackToTheDefault() {
    let defaults = UserDefaults.scratch("InterfaceLanguageTests")
    defaults.set("fr", forKey: InterfaceLanguage.key)
    #expect(InterfaceLanguage.chosen(in: defaults) == .simplifiedChinese)
  }

  /// What launch writes as the app's own `AppleLanguages`.
  @Test(arguments: [(nil, ["zh-Hans"]), ("en", ["en"]), ("zh-Hans", ["zh-Hans"])])
  func launchSetsTheAppLanguages(stored: String?, expected: [String]) {
    let defaults = UserDefaults.scratch("InterfaceLanguageTests")
    if let stored { defaults.set(stored, forKey: InterfaceLanguage.key) }
    #expect(InterfaceLanguage.appleLanguages(in: defaults) == expected)
  }

  /// Each option is named in its own language, whatever the UI language.
  @Test func optionsAreNamedInTheirOwnLanguage() {
    #expect(InterfaceLanguage.allCases.map(\.name) == ["简体中文", "English"])
  }

  @Test func matchesTheRunningLocalization() {
    #expect(InterfaceLanguage(localization: "zh-Hans") == .simplifiedChinese)
    #expect(InterfaceLanguage(localization: "en") == .english)
  }
}
