// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

struct LexiconTests {
  let lexicon: Lexicon

  init() throws {
    lexicon = try Lexicon(url: try LexiconFixture.write())
  }

  private func lemmas(_ term: String, context: String? = nil) async -> [String] {
    await lexicon.lookup(term, context: context).map(\.lemma)
  }

  @Test func exactHitReturnsTheWholeEntry() async {
    let entries = await lexicon.lookup("run", context: nil)
    #expect(
      entries == [
        LexiconEntry(
          lemma: "run", ipaUS: "/ɹʌn/", ipaUK: "/rʌn/", band: .common,
          senses: [
            LexiconSense(pos: "verb", gloss: "跑、奔跑", hint: "move swiftly", source: "en"),
            LexiconSense(pos: "noun", gloss: "跑步", hint: nil, source: "zh"),
          ])
      ])
  }

  @Test(arguments: [("ran", ["run"]), ("runs", ["run"]), ("went", ["go"]), ("took", ["take"])])
  func formsPointAtTheirLemma(form: String, expected: [String]) async {
    #expect(await lemmas(form) == expected)
  }

  @Test func ownEntryWithoutTranslationTableGoesLast() async {
    // taken (6.1) is more frequent than take (5.8) but has only a zh sense.
    #expect(await lemmas("taken") == ["take", "taken"])
  }

  @Test func ownEntryWithTranslationTableKeepsItsFrequencyRank() async {
    #expect(await lemmas("left") == ["left", "leave"])
  }

  @Test func equalFrequencyPutsTheLemmaFirst() async {
    #expect(await lemmas("rose") == ["rise", "rose"])
  }

  @Test(arguments: ["RUN", "Run", "  run\n", "“run,”", "(ran).", "run!?", "'run'", "…run…"])
  func ignoresCaseAndEdgePunctuation(term: String) async {
    #expect(await lemmas(term) == ["run"])
  }

  @Test func keepsInnerPunctuationAndSpaces() async {
    #expect(await lemmas("State-of-the-Art.") == ["state-of-the-art"])
    #expect(await lemmas("take  off") == ["take off"])
    #expect(await lemmas("Cafe\u{0301}") == ["café"])
  }

  @Test func lemmatizesUnlistedFormsWithNLTagger() async {
    #expect(await lemmas("running") == ["run"])
    #expect(await lemmas("Running,") == ["run"])
    #expect(await lemmas("took off") == ["take off"])
  }

  @Test func contextSentenceDisambiguatesTheLemma() async {
    #expect(await lemmas("leaves", context: "The leaves fell in the yard.") == ["leaf"])
    #expect(await lemmas("leaves", context: "He leaves for work early.") == ["leave"])
    #expect(await lemmas("Leaves", context: "Leaves turned red.") == ["leaf"])
    // A term the sentence does not contain is lemmatized on its own.
    #expect(await lemmas("leaves", context: "Something else entirely.") == ["leave"])
  }

  @Test func contextMatchesWholeWordsOnly() async {
    // "leaves" inside "sleeves" is not the selection; the term is tagged on its own.
    #expect(await lemmas("leaves", context: "Roll up your sleeves; the leaves fell.") == ["leaf"])
  }

  @Test(arguments: ["xyzzy", "", "   ", "...", "—", "flurbing"])
  func unknownTermsReturnNothing(term: String) async {
    #expect(await lexicon.lookup(term, context: nil).isEmpty)
  }

  @Test func bandsFollowZipf() async {
    #expect(await lexicon.lookup("run", context: nil).first?.band == .common)
    #expect(await lexicon.lookup("leaf", context: nil).first?.band == .moderate)
    #expect(await lexicon.lookup("café", context: nil).first?.band == .moderate)
    #expect(await lexicon.lookup("state-of-the-art", context: nil).first?.band == .rare)
    #expect(await lexicon.lookup("serendipity", context: nil).first?.band == .rare)
  }

  @Test(arguments: [
    (6.0, FrequencyBand.common), (4.5, .common), (4.49, .moderate), (3.5, .moderate),
    (3.49, .rare), (0, .rare),
  ])
  func bandThresholds(zipf: Double, expected: FrequencyBand) {
    #expect(FrequencyBand(zipf: zipf) == expected)
  }

  @Test func missingFrequencyIsRare() {
    #expect(FrequencyBand(zipf: nil) == .rare)
  }

  @Test func missingIPAIsNil() async {
    let take = await lexicon.lookup("take", context: nil).first
    #expect(take?.ipaUS == "/teɪk/")
    #expect(take?.ipaUK == nil)
  }

  @Test func sourcesComeFromMeta() async {
    #expect(
      await lexicon.sources() == [
        DataSource(
          name: "Wiktionary (en)", url: "https://kaikki.org/dictionary/English/",
          snapshotDate: "2026-10-02", sha256: "aa11", license: "CC BY-SA 4.0",
          licenseURL: "https://creativecommons.org/licenses/by-sa/4.0/"),
        DataSource(
          name: "FrequencyWords", url: "https://github.com/hermitdave/FrequencyWords",
          snapshotDate: "2018-01-01", sha256: "bb22", license: "CC BY-SA 4.0",
          licenseURL: "https://creativecommons.org/licenses/by-sa/4.0/"),
      ])
  }
}

struct LexiconOpeningTests {
  @Test func missingFileThrows() throws {
    let url = try LexiconFixture.temporaryDirectory().appending(path: "absent.sqlite")
    #expect(throws: LexiconError.self) { try Lexicon(url: url) }
    // Opening read-only never creates the file.
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test func fileThatIsNotSQLiteThrows() throws {
    let url = try LexiconFixture.temporaryDirectory().appending(path: "garbage.sqlite")
    try Data(repeating: 0x2A, count: 4096).write(to: url)
    #expect(throws: LexiconError.self) { try Lexicon(url: url) }
  }

  @Test func emptyFileThrows() throws {
    let url = try LexiconFixture.temporaryDirectory().appending(path: "empty.sqlite")
    try Data().write(to: url)
    #expect(throws: LexiconError.self) { try Lexicon(url: url) }
  }

  @Test func doesNotWriteTheDatabase() async throws {
    let url = try LexiconFixture.write()
    let before = try Data(contentsOf: url)
    let lexicon = try Lexicon(url: url)
    _ = await lexicon.lookup("ran", context: "She ran home.")
    _ = await lexicon.sources()
    #expect(try Data(contentsOf: url) == before)
  }
}
