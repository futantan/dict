// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

private func voice(
  _ name: String, _ language: String, _ quality: VoiceQuality = .compact,
  prefix: String? = nil, novelty: Bool = false
) -> VoiceInfo {
  let tier =
    switch quality {
    case .compact: "compact"
    case .enhanced: "enhanced"
    case .premium: "premium"
    }
  return VoiceInfo(
    identifier: prefix.map { "\($0)\(name)" } ?? "com.apple.voice.\(tier).\(language).\(name)",
    name: name, language: language, quality: quality, isNovelty: novelty)
}

private let english = Locale.Language(identifier: "en")

/// The English voices of a fresh macOS 26 install: every voice compact, plus the eloquence
/// family, the novelty voices and the legacy MacinTalk voices.
private let freshInstall: [VoiceInfo] = [
  voice("Karen", "en-AU", prefix: "com.apple.voice.super-compact.en-AU."),
  voice("Daniel", "en-GB"),
  voice("Eddy", "en-GB", prefix: "com.apple.eloquence.en-GB."),
  voice("Grandma", "en-GB", prefix: "com.apple.eloquence.en-GB."),
  voice("Moira", "en-IE", prefix: "com.apple.voice.super-compact.en-IE."),
  voice("Rishi", "en-IN"),
  voice("Albert", "en-US", prefix: "com.apple.speech.synthesis.voice.", novelty: true),
  voice("Bubbles", "en-US", prefix: "com.apple.speech.synthesis.voice.", novelty: true),
  voice("Eddy", "en-US", prefix: "com.apple.eloquence.en-US."),
  voice("Fred", "en-US", prefix: "com.apple.speech.synthesis.voice."),
  voice("Junior", "en-US", prefix: "com.apple.speech.synthesis.voice."),
  voice("Kathy", "en-US", prefix: "com.apple.speech.synthesis.voice."),
  voice("Samantha", "en-US"),
  voice("Tessa", "en-ZA", prefix: "com.apple.voice.super-compact.en-ZA."),
]

struct ResolveVoiceTests {
  @Test(arguments: [
    (Accent.american, "Samantha", VoiceHint?.some(.higherQuality)),
    (.british, "Daniel", .higherQuality),
    (.australian, "Karen", .higherQuality),
    (.indian, "Rishi", .higherQuality),
    // No en-CA voice: fall back to the language's default region.
    (.canadian, "Samantha", .accentMissing),
  ])
  func picksTheAccentOnAFreshInstall(accent: Accent, name: String, hint: VoiceHint?) {
    let choice = resolveVoice(language: english, accent: accent, installed: freshInstall)
    #expect(choice.voice?.name == name)
    #expect(choice.hint == hint)
  }

  @Test(arguments: [
    // The highest tier wins within the accent.
    (
      [
        voice("Samantha", "en-US"), voice("Ava", "en-US", .premium),
        voice("Zoe", "en-US", .enhanced),
      ],
      "Ava", VoiceHint?.none
    ),
    // Enhanced is good enough: no nudge to download.
    ([voice("Samantha", "en-US"), voice("Zoe", "en-US", .enhanced)], "Zoe", nil),
    // The accent beats a better tier in another region.
    ([voice("Daniel", "en-GB", .premium), voice("Samantha", "en-US")], "Samantha", .higherQuality),
    // Ties within a tier go by name, so the choice is stable.
    ([voice("Zack", "en-US"), voice("Allison", "en-US")], "Allison", .higherQuality),
  ])
  func ranksWithinTheAccent(installed: [VoiceInfo], name: String, hint: VoiceHint?) {
    let choice = resolveVoice(language: english, accent: .american, installed: installed)
    #expect(choice.voice?.name == name)
    #expect(choice.hint == hint)
  }

  @Test func neverPicksNoveltyEloquenceOrLegacyOverAModernVoice() {
    let installed = [
      voice("Bubbles", "en-US", .premium, prefix: "x.", novelty: true),
      voice("Flo", "en-US", .premium, prefix: "com.apple.eloquence.en-US."),
      voice("Fred", "en-US", prefix: "com.apple.speech.synthesis.voice."),
      voice("Samantha", "en-US"),
    ]
    let choice = resolveVoice(language: english, accent: .american, installed: installed)
    #expect(choice.voice?.name == "Samantha")
  }

  @Test func aLegacyVoiceIsTheLastResort() {
    let installed = [
      voice("Bubbles", "en-US", prefix: "x.", novelty: true),
      voice("Fred", "en-US", prefix: "com.apple.speech.synthesis.voice."),
    ]
    let choice = resolveVoice(language: english, accent: .american, installed: installed)
    #expect(choice.voice?.name == "Fred")
  }

  @Test(arguments: [
    // The default region first, then other regions by tier, then by region code.
    ([voice("Daniel", "en-GB"), voice("Samantha", "en-US")], "Samantha"),
    ([voice("Karen", "en-AU"), voice("Daniel", "en-GB", .enhanced)], "Daniel"),
    ([voice("Rishi", "en-IN"), voice("Karen", "en-AU")], "Karen"),
  ])
  func fallsBackWhenTheAccentIsMissing(installed: [VoiceInfo], name: String) {
    let choice = resolveVoice(language: english, accent: .canadian, installed: installed)
    #expect(choice.voice?.name == name)
    #expect(choice.hint == .accentMissing)
  }

  @Test(arguments: [
    // Only novelty and eloquence voices speak English: nothing usable.
    [
      voice("Bubbles", "en-US", prefix: "x.", novelty: true),
      voice("Eddy", "en-US", prefix: "com.apple.eloquence.en-US."),
    ],
    [voice("Thomas", "fr-FR"), voice("Anna", "de-DE")],
    [],
  ])
  func reportsNoVoice(installed: [VoiceInfo]) {
    let choice = resolveVoice(language: english, accent: .american, installed: installed)
    #expect(choice == VoiceChoice(voice: nil, hint: .noVoice))
  }

  @Test(arguments: [
    // Without an accent the language's own region decides, then its default region.
    ("fr-CA", "Amélie"),
    ("fr", "Thomas"),
    ("zh-Hans", "Tingting"),
    ("zh-Hant", "Meijia"),
    ("zh-HK", "Sinji"),
  ])
  func otherLanguagesUseTheirRegion(language: String, name: String) {
    let installed = [
      voice("Amélie", "fr-CA"), voice("Thomas", "fr-FR"), voice("Tingting", "zh-CN"),
      voice("Meijia", "zh-TW"), voice("Sinji", "zh-HK"), voice("Samantha", "en-US"),
    ]
    let choice = resolveVoice(
      language: Locale.Language(identifier: language), accent: nil, installed: installed)
    #expect(choice.voice?.name == name)
    #expect(choice.hint == .higherQuality)
  }

  @Test func theAccentOnlyAppliesToEnglish() {
    let installed = [voice("Thomas", "fr-FR"), voice("Amélie", "fr-CA")]
    let choice = resolveVoice(
      language: Locale.Language(identifier: "fr"), accent: .british, installed: installed)
    #expect(choice.voice?.name == "Thomas")
  }

  @Test func theAccentOverridesTheLanguageRegion() {
    let choice = resolveVoice(
      language: Locale.Language(identifier: "en-US"), accent: .british, installed: freshInstall)
    #expect(choice.voice?.name == "Daniel")
  }

  @Test func withoutAnAccentEnglishUsesItsRegion() {
    let choice = resolveVoice(
      language: Locale.Language(identifier: "en-GB"), accent: nil, installed: freshInstall)
    #expect(choice.voice?.name == "Daniel")
  }

  @Test func readsUnderscoredLanguageTags() {
    let choice = resolveVoice(
      language: english, accent: .british, installed: [voice("Daniel", "en_GB")])
    #expect(choice.voice?.name == "Daniel")
    #expect(choice.hint == .higherQuality)
  }
}
