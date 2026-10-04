// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictBuild

/// End to end over the hand-written fixtures: two wiktextract files (one per heading) and a
/// tiny frequency list. The fixtures are made up in the extraction's format; no real
/// Wiktionary data is checked in.
struct BuildTests {
  static let fixtures = Bundle.module.bundleURL.appending(path: "Fixtures")

  static func entries(_ name: String) throws -> [WiktionaryEntry] {
    var entries: [WiktionaryEntry] = []
    try forEachLine(of: fixtures.appending(path: name)) {
      entries.append(try JSONDecoder().decode(WiktionaryEntry.self, from: $0))
    }
    return entries
  }

  static func lexicon(blocklist: Set<String> = []) throws -> Lexicon {
    var builder = LexiconBuilder()
    for entry in try entries("en-hant.jsonl") + entries("en-hans.jsonl") { builder.add(entry) }
    let frequencies = try FrequencyTable(contentsOf: fixtures.appending(path: "frequency.txt"))
    return builder.build(zipf: frequencies.zipf, blocklist: blocklist)
  }

  static func headword(_ key: String, in lexicon: Lexicon) throws -> Headword {
    try #require(lexicon.headwords.first { $0.key == key })
  }

  @Test func keepsOnlyEnglishEntriesWithUsableSenses() throws {
    let lexicon = try Self.lexicon()
    #expect(
      lexicon.headwords.map(\.key) == [
        "absite", "arena", "be", "best", "better", "child", "color", "created", "good",
        "hospital", "light", "rin", "run", "server", "take off", "turkey",
      ])
  }

  @Test func mergesBothHeadingsAndDeduplicatesAfterSimplifying() throws {
    let lexicon = try Self.lexicon()
    #expect(try Self.headword("hospital", in: lexicon).senses == [Sense(pos: "noun", gloss: "医院")])
    #expect(
      try Self.headword("run", in: lexicon).senses == [
        Sense(pos: "verb", gloss: "奔跑"), Sense(pos: "verb", gloss: "经营；管理"),
        Sense(pos: "noun", gloss: "跑步"), Sense(pos: "noun", gloss: "奔跑"),
      ])
  }

  @Test func mergesSpellingsThatShareAKey() throws {
    let turkey = try Self.headword("turkey", in: try Self.lexicon())
    #expect(turkey.lemma == "turkey")
    #expect(turkey.wikiTitle == "turkey")
    #expect(turkey.senses.map(\.gloss) == ["火鸡", "土耳其"])
    #expect(turkey.ipaUK == "/ˈtɜːki/")
    #expect(turkey.ipaUS == "/ˈtɝki/")
  }

  @Test func cleansAndClassifiesSenses() throws {
    let lexicon = try Self.lexicon()
    #expect(try Self.headword("arena", in: lexicon).senses == [Sense(pos: "noun", gloss: "竞技场")])
    #expect(try Self.headword("absite", in: lexicon).senses == [Sense(pos: "", gloss: "钍钛铀矿")])
    #expect(
      try Self.headword("take off", in: lexicon).senses.map(\.pos) == [
        "phrasal verb", "phrasal verb",
      ])
    #expect(try Self.headword("good", in: lexicon).senses.map(\.gloss) == ["好的", "（美口） （俚） 够了"])
  }

  @Test func separatesAccents() throws {
    let lexicon = try Self.lexicon()
    let hospital = try Self.headword("hospital", in: lexicon)
    #expect(hospital.ipaUK == "/ˈhɒs.pɪ.tl̩/")
    #expect(hospital.ipaUS == "/ˈhɑs.pɪ.tl̩/")
    let run = try Self.headword("run", in: lexicon)
    #expect(run.ipaUK == "/ɹʌn/")
    #expect(run.ipaUS == "/ɹʌn/")
    let child = try Self.headword("child", in: lexicon)
    #expect(child.ipaUK == "/t͡ʃaɪld/")
    #expect(child.ipaUS == "/t͡ʃaɪld/")
    #expect(try Self.headword("absite", in: lexicon).ipaUK == nil)
  }

  @Test func indexesInflectionsAndSpellingsBackToTheirLemma() throws {
    let forms = try Self.lexicon().forms
    #expect(
      forms == [
        FormLink(formKey: "best", lemmaKey: "good"),
        FormLink(formKey: "better", lemmaKey: "good"),
        FormLink(formKey: "children", lemmaKey: "child"),
        FormLink(formKey: "colour", lemmaKey: "color"),
        FormLink(formKey: "ran", lemmaKey: "run"),
        FormLink(formKey: "running", lemmaKey: "run"),
        FormLink(formKey: "runs", lemmaKey: "run"),
        FormLink(formKey: "was", lemmaKey: "be"),
      ])
  }

  @Test func ignoresParadigmTablesOfNonBaseForms() throws {
    // `best` lists good (原級) and better; neither is an inflection of best.
    #expect(!(try Self.lexicon().forms.contains { $0.lemmaKey == "best" }))
  }

  @Test func dropsFormLinksToMuchRarerLemmas() throws {
    // ran is frequent, rin (Scots) is not in the frequency list at all.
    #expect(!(try Self.lexicon().forms.contains(FormLink(formKey: "ran", lemmaKey: "rin"))))
    #expect(try Self.headword("rin", in: try Self.lexicon()).senses.count == 1)
  }

  @Test func properNounOnlyEntriesGiveWayToInflections() throws {
    // "Was" (a surname) would hide was → be at the headword step of the lookup.
    #expect(!(try Self.lexicon().headwords.contains { $0.key == "was" }))
  }

  @Test func expandsLeakedTemplatesAndGrammarCodes() throws {
    let lexicon = try Self.lexicon()
    #expect(try Self.headword("light", in: lexicon).senses.map(\.gloss) == ["光；光线；光亮", "窗；天窗"])
    #expect(try Self.headword("created", in: lexicon).senses.map(\.gloss) == ["创建"])
    #expect(try Self.headword("server", in: lexicon).senses.map(\.gloss) == ["（计算机）伺服器", "侍者"])
  }

  @Test func blocklistRemovesAHeadwordAndItsForms() throws {
    let lexicon = try Self.lexicon(blocklist: ["run", "colour"])
    #expect(!lexicon.headwords.contains { $0.key == "run" })
    #expect(!lexicon.forms.contains { $0.lemmaKey == "run" || $0.formKey == "colour" })
  }

  @Test func storesZipfFromMergedCounts() throws {
    let lexicon = try Self.lexicon()
    #expect(try Self.headword("hospital", in: lexicon).zipf == 6.4)
    #expect(try Self.headword("take off", in: lexicon).zipf == nil)
    // Seen once: counted in the corpus size, but too rare to keep by default.
    #expect(try Self.headword("absite", in: lexicon).zipf == nil)
    let everything = try FrequencyTable(
      contentsOf: Self.fixtures.appending(path: "frequency.txt"), minimumCount: 1)
    #expect(everything.zipf("absite") == 2.92)
    #expect(everything.zipf("hospital") == 6.4)
    #expect(everything.ranked.prefix(3) == ["you", "the", "run"])
  }

  @Test(
    arguments: [
      (6.0, FrequencyBand.common), (4.5, .common), (4.49, .moderate), (3.5, .moderate),
      (3.49, .rare), (nil, .rare),
    ] as [(Double?, FrequencyBand)])
  func bandsZipfValues(zipf: Double?, band: FrequencyBand) {
    #expect(FrequencyBand(zipf: zipf) == band)
  }

  @Test func readsLinesAcrossChunkBoundariesAndWithoutTrailingNewline() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "lines-\(UUID()).txt")
    defer { try? FileManager.default.removeItem(at: url) }
    let line = String(repeating: "x", count: 999)
    try (Array(repeating: line, count: 3000).joined(separator: "\n") + "\n\nlast").write(
      to: url, atomically: true, encoding: .utf8)
    var count = 0
    var last = ""
    try forEachLine(of: url) {
      count += 1
      last = String(decoding: $0, as: UTF8.self)
    }
    #expect(count == 3001)
    #expect(last == "last")
  }
}
