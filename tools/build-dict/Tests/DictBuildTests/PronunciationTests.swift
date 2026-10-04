// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import DictBuild

struct PronunciationTests {
  @Test func readsNormalizedAndFreeTextLabels() {
    #expect(accents(tags: ["Received-Pronunciation"], rawTags: []) == [.uk])
    #expect(accents(tags: ["General-American"], rawTags: []) == [.us])
    #expect(accents(tags: ["US"], rawTags: ["英國"]) == [.uk, .us])
    #expect(accents(tags: [], rawTags: ["英"]) == [.uk])
    #expect(accents(tags: [], rawTags: ["美", "加"]) == [.us])
    #expect(accents(tags: [], rawTags: ["en，英國"]) == [.uk])
    #expect(accents(tags: [], rawTags: ["通用美式，加拿大"]) == [.us])
    #expect(accents(tags: [], rawTags: ["標準南英音", "北英格蘭"]) == [.uk])
  }

  @Test func regionalLabelsMatchNeitherAccent() {
    #expect(accents(tags: ["Australia"], rawTags: []).isEmpty)
    #expect(accents(tags: [], rawTags: ["北英格蘭"]).isEmpty)
    #expect(accents(tags: [], rawTags: ["紐西蘭"]).isEmpty)
    #expect(accents(tags: [], rawTags: ["cot–caught合併"]).isEmpty)
  }

  @Test func separatesBritishAndAmerican() {
    let ipa = pickIPA([
      Sound(ipa: "/ˈhɒs.pɪ.tl̩/", tags: ["Received-Pronunciation"]),
      Sound(ipa: "/ˈɒs.pɪ.tl̩/", rawTags: ["過時，標準英音"]),
      Sound(ipa: "/ˈhɑs.pɪ.tl̩/", tags: ["General-American"]),
      Sound(ipa: "/ˈhɑs.pɪ.t̬l̩/", tags: ["General-American"]),
    ])
    #expect(ipa.uk == "/ˈhɒs.pɪ.tl̩/")
    #expect(ipa.us == "/ˈhɑs.pɪ.tl̩/")
  }

  @Test func unlabelledPronunciationFillsOnlyMissingAccents() {
    let ipa = pickIPA([
      Sound(ipa: "/ˈt͡ʃɪldɹən/"), Sound(ipa: "/ˈt͡ʃʊldɹən/", tags: ["Australia"]),
      Sound(ipa: "/ˈtʃɪldrən/", tags: ["UK"]),
    ])
    #expect(ipa.uk == "/ˈtʃɪldrən/")
    #expect(ipa.us == "/ˈt͡ʃɪldɹən/")
  }

  @Test func ignoresPhoneticAndCombinedTranscriptions() {
    let ipa = pickIPA([
      Sound(ipa: "[tʃɪl.ɹən]", tags: ["US"]), Sound(ipa: "/a/, /b/", tags: ["UK"]),
      Sound(ipa: nil, tags: ["US"]),
    ])
    #expect(ipa.uk == nil)
    #expect(ipa.us == nil)
  }
}
