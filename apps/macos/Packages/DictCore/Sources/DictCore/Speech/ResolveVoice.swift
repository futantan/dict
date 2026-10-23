// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Picks the voice to speak `language` with from the installed voices (architecture 9).
///
/// The accent applies to English only; without one the language's own region decides, and a
/// bare language takes its likely region (en → US). Joke voices and the eloquence family are
/// never picked; the legacy MacinTalk voices only when nothing else speaks the language.
/// Ranking: the wanted region, then the language's default region, then any other region;
/// within that the highest tier (premium > enhanced > compact), modern before legacy, then by
/// region code and name so the choice is stable.
public func resolveVoice(
  language: Locale.Language, accent: Accent?, installed: [VoiceInfo]
) -> VoiceChoice {
  guard let code = language.languageCode else { return VoiceChoice(voice: nil, hint: .noVoice) }
  let accentRegion = code == .english ? accent?.region : nil
  let wanted = accentRegion ?? likelyRegion(of: language)
  let fallback = likelyRegion(of: Locale.Language(languageCode: code))

  let candidates = installed.compactMap { voice -> Candidate? in
    let voiceLanguage = Locale.Language(identifier: voice.language)
    guard voiceLanguage.languageCode == code, !voice.isNovelty,
      !voice.identifier.hasPrefix("com.apple.eloquence.")
    else { return nil }
    return Candidate(voice: voice, region: voiceLanguage.region?.identifier ?? "")
  }
  let best = candidates.min { lhs, rhs in
    lhs.key(wanted: wanted, fallback: fallback) < rhs.key(wanted: wanted, fallback: fallback)
  }
  guard let best else { return VoiceChoice(voice: nil, hint: .noVoice) }

  return VoiceChoice(voice: best.voice, hint: hint(for: best, wanted: wanted))
}

private func hint(for best: Candidate, wanted: String?) -> VoiceHint? {
  if best.region != wanted { return .accentMissing }
  if best.voice.quality == .compact { return .higherQuality }
  return nil
}

private struct Candidate {
  var voice: VoiceInfo
  var region: String

  func key(wanted: String?, fallback: String?) -> SortKey {
    SortKey(
      regionRank: region == wanted ? 0 : region == fallback ? 1 : 2,
      tier: -voice.quality.rawValue,
      legacy: voice.identifier.hasPrefix("com.apple.speech.synthesis.voice.") ? 1 : 0,
      region: region, name: voice.name)
  }
}

private struct SortKey: Comparable {
  var regionRank: Int
  var tier: Int
  var legacy: Int
  var region: String
  var name: String

  static func < (lhs: SortKey, rhs: SortKey) -> Bool {
    (lhs.regionRank, lhs.tier, lhs.legacy, lhs.region, lhs.name)
      < (rhs.regionRank, rhs.tier, rhs.legacy, rhs.region, rhs.name)
  }
}

private func likelyRegion(of language: Locale.Language) -> String? {
  Locale.Language(identifier: language.maximalIdentifier).region?.identifier
}
