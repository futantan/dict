// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Testing

@testable import DictApp

private let run = LexiconEntry(
  lemma: "run", ipaUS: "/ɹʌn/", ipaUK: "/rʌn/", band: .common,
  senses: [
    LexiconSense(pos: "verb", gloss: "跑、奔跑、走", source: "en"),
    LexiconSense(pos: "verb", gloss: "流", source: "en"),
    LexiconSense(pos: "verb", gloss: "经营、管理", source: "en"),
    LexiconSense(pos: "noun", gloss: "拉丝", source: "en"),
  ])

private let card = WordCard(
  status: .ok, lemma: "run", phonetic: "/rʌn/", partOfSpeech: "verb", definition: "经营；管理",
  contextTranslation: "她经营一家小面包店。",
  otherSenses: [WordCard.Sense(partOfSpeech: "verb", definition: "跑")],
  examples: [WordCard.Example(sentence: "Who runs this shop?", translation: "这家店谁在经营？")],
  collocations: [WordCard.Collocation(phrase: "run a business", meaning: "经营生意")],
  level: "B1")

struct CardStateTests {
  @Test func theDictionaryLayerShowsTheFirstSensesInTheAccent() {
    let state = CardState(
      term: "ran", context: "She ran a bakery.", entry: run, accent: .american, model: .loading)
    #expect(state.lemma == "run")
    #expect(state.phonetic == "/ɹʌn/")
    #expect(state.senses.map(\.gloss) == ["跑、奔跑、走", "流", "经营、管理"])
    #expect(state.band == .common)
    #expect(state.hasDictionary)

    let british = CardState(
      term: "ran", context: nil, entry: run, accent: .british, model: .loading)
    #expect(british.phonetic == "/rʌn/")
  }

  @Test func eitherTranscriptionStandsInForTheOther() {
    var entry = run
    entry.ipaUK = nil
    #expect(CardState.phonetic(entry, accent: .australian) == "/ɹʌn/")
    entry.ipaUS = ""
    #expect(CardState.phonetic(entry, accent: .american) == nil)
  }

  @Test func theStreamedFieldsComeFirst() {
    var state = CardState(term: "ran", context: nil, entry: run, accent: .american, model: .loading)
    state.show(definition: "经营；管理", contextTranslation: nil)
    #expect(state.definition == "经营；管理")
    #expect(state.contextTranslation == nil)
    #expect(state.otherSenses.isEmpty)
    #expect(state.model == .loading)
  }

  @Test func theCompleteCardKeepsTheDictionaryPronunciation() {
    var state = CardState(term: "ran", context: nil, entry: run, accent: .american, model: .loading)
    state.show(card)
    #expect(state.phonetic == "/ɹʌn/")
    #expect(state.contextTranslation == "她经营一家小面包店。")
    #expect(state.examples == card.examples)
    #expect(state.collocations == card.collocations)
    #expect(state.model == .complete)
  }

  @Test func rareWordsHideTheCollocations() {
    var entry = run
    entry.band = .rare
    var state = CardState(term: "x", context: nil, entry: entry, accent: .american, model: .loading)
    state.show(card)
    #expect(state.collocations.isEmpty)
    #expect(state.otherSenses == card.otherSenses)
  }

  @Test func withoutTheDictionaryTheModelNamesAndVoicesTheTerm() {
    var state = CardState(
      term: "took off", context: nil, entry: nil, accent: .american, model: .loading)
    #expect(state.lemma == "took off")
    #expect(!state.hasDictionary)
    state.show(card)
    #expect(state.lemma == "run")
    #expect(state.phonetic == "/rʌn/")
    #expect(state.collocations == card.collocations)
  }

  @Test func theCountShowsFromTheSecondLookup() {
    var state = CardState(term: "ran", context: nil, entry: run, accent: .american, model: .loading)
    #expect(state.shownEncounters == nil)
    state.encounters = 1
    #expect(state.shownEncounters == nil)
    state.encounters = 2
    #expect(state.shownEncounters == 2)
  }

  @Test func copyingTakesTheTitleAndTheFirstMeaning() {
    var state = CardState(term: "ran", context: nil, entry: run, accent: .american, model: .loading)
    #expect(state.copyableText == "run\n跑、奔跑、走")
    state.show(definition: "经营；管理", contextTranslation: nil)
    #expect(state.copyableText == "run\n经营；管理")
  }
}
