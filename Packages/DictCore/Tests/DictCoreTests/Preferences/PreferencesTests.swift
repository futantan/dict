// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

struct PreferencesTests {
  private func decode(_ json: String) throws -> Preferences {
    try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
  }

  @Test func defaultsAreSimplifiedChineseLearningAmericanEnglishWithoutModel() {
    let preferences = Preferences()

    #expect(preferences.myLanguage == "zh-Hans")
    #expect(preferences.learningLanguage == "en")
    #expect(preferences.accent == .american)
    #expect(preferences.model.providerID == nil)
    #expect(preferences.keepsFormatting)
    #expect(preferences.languagePair == LanguagePair())
  }

  @Test func roundTrips() throws {
    var preferences = Preferences()
    preferences.myLanguage = "ja"
    preferences.learningLanguage = "fr"
    preferences.accent = .british
    preferences.model = ModelPreferences(
      providerID: "custom", model: "deepseek-chat", baseURL: "https://api.deepseek.com/v1")
    preferences.keepsFormatting = false

    let data = try JSONEncoder().encode(preferences)

    #expect(try JSONDecoder().decode(Preferences.self, from: data) == preferences)
  }

  @Test func encodesStableFieldNames() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let preferences = Preferences(
      model: ModelPreferences(providerID: "openai", model: "", baseURL: ""))

    let json = String(decoding: try encoder.encode(preferences), as: UTF8.self)

    #expect(
      json
        == #"{"accent":"american","keepsFormatting":true,"learningLanguage":"en","#
        + #""model":{"baseURL":"","model":"","providerID":"openai"},"myLanguage":"zh-Hans"}"#)
  }

  @Test func missingFieldsTakeDefaults() throws {
    #expect(try decode("{}") == Preferences())
    #expect(try decode(#"{"model": {}}"#) == Preferences())

    let partial = try decode(#"{"learningLanguage": "de", "model": {"providerID": "ollama"}}"#)
    #expect(partial.myLanguage == "zh-Hans")
    #expect(partial.learningLanguage == "de")
    #expect(partial.model == ModelPreferences(providerID: "ollama"))
  }

  /// Preferences saved before the setting existed, or unreadable, keep the formatting.
  @Test func keepingTheFormattingIsOnUnlessSavedOff() throws {
    #expect(try decode(#"{"myLanguage": "ja"}"#).keepsFormatting)
    #expect(try decode(#"{"keepsFormatting": "no"}"#).keepsFormatting)
    #expect(try decode(#"{"keepsFormatting": false}"#).keepsFormatting == false)
  }

  @Test func unknownAccentFallsBackToDefault() throws {
    #expect(try decode(#"{"accent": "martian"}"#).accent == .american)
  }

  @Test func ignoresUnknownFields() throws {
    #expect(try decode(#"{"futureSetting": true, "myLanguage": "ko"}"#).myLanguage == "ko")
  }

  @Test func languagePairUsesTheChosenIdentifiers() {
    let preferences = Preferences(myLanguage: "en", learningLanguage: "zh-Hant")

    #expect(preferences.languagePair.mine == Locale.Language(identifier: "en"))
    #expect(preferences.languagePair.learning == Locale.Language(identifier: "zh-Hant"))
  }

  @Test func choosingTheOtherLanguageSwapsThePair() {
    var preferences = Preferences()

    preferences.setMyLanguage("en")
    #expect(preferences.myLanguage == "en")
    #expect(preferences.learningLanguage == "zh-Hans")

    preferences.setLearningLanguage("en")
    #expect(preferences.myLanguage == "zh-Hans")
    #expect(preferences.learningLanguage == "en")

    preferences.setLearningLanguage("ja")
    #expect(preferences.myLanguage == "zh-Hans")
    #expect(preferences.learningLanguage == "ja")
  }

  @Test func languageListHasTheDefaultsAndNoDuplicates() {
    let languages = Preferences.languages

    #expect(languages.contains("zh-Hans"))
    #expect(languages.contains("en"))
    #expect(Set(languages).count == languages.count)
  }

  @Test(arguments: Accent.allCases)
  func accentRegionsAreUppercaseRegionCodes(accent: Accent) {
    #expect(accent.region.count == 2)
    #expect(accent.region == accent.region.uppercased())
    #expect(accent.language == Locale.Language(identifier: "en-\(accent.region)"))
  }
}
