// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictBuild

/// Merging the English Wiktionary's translation tables (`en-en.jsonl`) with Chinese Wiktionary
/// definitions (`zh-merge.jsonl`). Both fixtures are hand-written in the extraction's format.
struct MergeTests {
  static let zipf: [String: Double] = [
    "go": 6.6, "went": 5.9, "take": 6.3, "taken": 6.4, "bad": 5.8, "worse": 6.0, "goose": 3.5,
    "geese": 3.4, "wend": 1.5,
  ]

  static func lexicon(blocklist: Set<String> = []) throws -> Lexicon {
    var builder = LexiconBuilder()
    for entry in try BuildTests.entries("zh-merge.jsonl") { builder.add(entry, from: .zh) }
    for entry in try BuildTests.entries("en-en.jsonl") { builder.add(entry, from: .en) }
    return builder.build(zipf: { zipf[$0] }, blocklist: blocklist)
  }

  static func glosses(_ key: String, in lexicon: Lexicon) throws -> [String] {
    try BuildTests.headword(key, in: lexicon).senses.map(\.gloss)
  }

  @Test func ranksTablesByLanguagesNotByTheSenseTheyWereAttachedTo() throws {
    // 光 sits under "a cigarette lighter" in the extraction, but its table has 4 languages
    // against 2 for "point of view".
    let light = try Self.headword("light")
    #expect(light.senses.map(\.gloss) == ["光", "观点", "光；光线；光亮"])
    #expect(light.senses.map(\.hint) == ["electromagnetic waves", "point of view", nil])
  }

  @Test func putsTablesBeforeDefinitionsAndDropsSensesAlreadyCovered() throws {
    // zh 奔跑 is covered by the table 跑、奔跑; 经营；管理 is new.
    #expect(try Self.glosses("run") == ["跑、奔跑", "经营；管理"])
    #expect(try Self.headword("run").senses.map(\.source) == [.en, .zh])
  }

  @Test func countsEveryLanguageButTakesOnlyMandarinWords() throws {
    // institution: Mandarin, French, German, Cantonese (Dungan shares the zh code) = 4;
    // edge of river: 2; the branch-office table repeats 银行 and is dropped.
    let bank = try Self.headword("bank")
    #expect(
      bank.senses == [
        Sense(pos: "noun", gloss: "银行", source: .en, hint: "institution"),
        Sense(pos: "noun", gloss: "岸", source: .en, hint: "edge of river or lake"),
      ])
  }

  @Test func cleansTableCells() throws {
    // Alternatives joined by & lose their qualifiers, regional words go last, obsolete ones,
    // editor notes and words without a Chinese character go.
    #expect(try Self.glosses("play") == ["弹、弹奏、掷、扔、演奏"])
  }

  @Test(
    arguments: [
      ("銀行 /银行", ["银行"]), ("光", ["光"]), ("彈 /弹&(formal)彈奏 /弹奏", ["弹", "弹奏"]),
      ("擲 /掷&(colloquial&informal) 扔", ["掷", "扔"]), ("OK (ōukèi)", []),
      ("but see 美國 /美国", []), ("在……之內 /在……之内", ["在……之内"]), ("T恤", ["T恤"]),
      ("計程車", ["计程车"]), ("{{t+|1=cmn|2=极简主义}}", []), ("凶暴[[]]的人", []),
    ])
  func readsMandarinCells(cell: String, words: [String]) {
    #expect(mandarinWords(cell) == words)
  }

  @Test func demotesSurnamesLoneCharactersAndProperNouns() throws {
    // The zh surname gloss and the proper-noun table of `Long` go after the adjective.
    #expect(try Self.glosses("long") == ["长", "久、长", "转变自昵称的姓氏", "朗"])
    // Lone characters from a list of near-synonyms go after the definition.
    #expect(try Self.glosses("peaceful") == ["和平的", "康", "宁"])
  }

  @Test func linksInflectionsFromTheEnglishEdition() throws {
    let forms = Set(try Self.lexicon().forms)
    for (form, lemma) in [
      ("went", "go"), ("goes", "go"), ("going", "go"), ("gone", "go"), ("geese", "goose"),
      ("worse", "bad"), ("worst", "bad"), ("taken", "take"), ("banks", "bank"),
      ("grilled", "grill"), ("grey", "gray"),
    ] {
      #expect(forms.contains(FormLink(formKey: form, lemmaKey: lemma)), "\(form) → \(lemma)")
    }
    // Archaic (went → wend) and nonstandard (goed) forms point nowhere.
    #expect(!forms.contains(FormLink(formKey: "went", lemmaKey: "wend")))
    #expect(!forms.contains { $0.formKey == "goed" || $0.formKey == "glossary" })
    // A regional spelling (Scots girl for grill) and an acronym of several words are not
    // spellings of a lemma.
    #expect(!forms.contains(FormLink(formKey: "girl", lemmaKey: "grill")))
    #expect(!forms.contains { $0.formKey == "halt" || $0.formKey == "usage notes" })
  }

  @Test func keepsAnInflectionsOwnEntryAndItsLinkToTheLemma() throws {
    // `taken` and `worse` have meanings of their own; the lookup also needs take and bad.
    let lexicon = try Self.lexicon()
    #expect(try Self.glosses("taken", in: lexicon) == ["迷上"])
    #expect(try Self.glosses("worse", in: lexicon) == ["更坏、更糟"])
    #expect(lexicon.forms.contains(FormLink(formKey: "taken", lemmaKey: "take")))
    #expect(lexicon.forms.contains(FormLink(formKey: "worse", lemmaKey: "bad")))
  }

  @Test func looksUpByFrequencyButPutsBareInflectionsLast() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "merge-\(UUID()).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    try writeDatabase(try Self.lexicon(), meta: [:], to: url)
    func lemmas(_ term: String) throws -> [String] { try lookup(term, database: url).map(\.lemma) }
    // worse has a table of its own and is the more frequent (in this fixture).
    #expect(try lemmas("worse") == ["worse", "bad"])
    // taken is more frequent than take, but its entry has no table of its own.
    #expect(try lemmas("taken") == ["take", "taken"])
    #expect(try lemmas("geese") == ["goose"])
  }

  @Test func blocklistCanDropOneWrongGloss() throws {
    #expect(try Self.glosses("go") == ["去", "围棋", "围旗"])
    let lexicon = try Self.lexicon(blocklist: ["go\t围旗"])
    #expect(try Self.glosses("go", in: lexicon) == ["去", "围棋"])
  }

  @Test func prefersEnglishEditionPronunciations() throws {
    let run = try Self.headword("run")
    #expect(run.ipaUK == "/ɹʌn/")
    #expect(run.ipaUS == "/ɹʌn/")
    let bank = try Self.headword("bank")
    #expect(bank.ipaUK == "/ˈbæŋk/")
    #expect(bank.ipaUS == "/ˈbæŋk/")
  }

  @Test func properNounsThatAreFormsOfEachOtherBothStay() throws {
    // France lists Frances as its plural and Frances lists France as a spelling; neither is
    // an inflection of a common word, so neither gives way (unlike Was → be).
    #expect(try Self.glosses("france") == ["法国"])
    #expect(try Self.glosses("frances") == ["弗朗西丝"])
  }

  @Test func leavesOutWordsWithNothingToShowAndOtherLanguages() throws {
    let keys = try Self.lexicon().headwords.map(\.key)
    #expect(!keys.contains("zyzzyva"))
    #expect(!keys.contains("chat"))
    #expect(!keys.contains("went"))
    #expect(!keys.contains("geese"))
  }

  static func headword(_ key: String) throws -> Headword {
    try BuildTests.headword(key, in: try lexicon())
  }

  static func glosses(_ key: String) throws -> [String] {
    try glosses(key, in: try lexicon())
  }
}
