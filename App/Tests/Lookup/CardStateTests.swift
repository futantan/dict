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

  /// The tag before the pronunciation names the transcription shown, which is the other one
  /// when the accent's is missing; the model's pronunciation has none.
  @Test func thePronunciationIsTaggedWithItsTranscription() {
    func transcription(_ accent: Accent, _ change: (inout LexiconEntry) -> Void = { _ in })
      -> CardState.Transcription?
    {
      var entry = run
      change(&entry)
      return CardState(term: "ran", context: nil, entry: entry, accent: accent, model: .loading)
        .transcription
    }
    #expect(transcription(.american) == .us)
    #expect(transcription(.canadian) == .us)
    #expect(transcription(.british) == .uk)
    #expect(transcription(.indian) == .uk)
    #expect(transcription(.american) { $0.ipaUS = "" } == .uk)
    #expect(transcription(.british) { $0.ipaUK = nil } == .us)
    #expect(
      transcription(.british) {
        $0.ipaUK = nil
        $0.ipaUS = nil
      } == nil)

    var typed = CardState(
      term: "took off", context: nil, entry: nil, accent: .american, model: .loading)
    typed.show(card)
    #expect(typed.phonetic == "/rʌn/")
    #expect(typed.transcription == nil)
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

  @Test func withTheDictionaryTheModelDefinitionIsTheMeaningInTheSentence() {
    var state = CardState(
      term: "ran", context: "She ran a bakery.", entry: run, accent: .american, model: .loading)
    #expect(state.mainSenses == state.senses)
    #expect(state.sentenceMeaning == nil)
    #expect(state.showsSentenceSection)
    state.show(card)
    #expect(state.mainSenses == state.senses)
    #expect(state.sentenceMeaning == "经营；管理")
    #expect(state.showsSentenceSection)
  }

  @Test func withoutTheDictionaryTheModelDefinitionLeadsTheCard() {
    var state = CardState(
      term: "ran", context: "She ran a bakery.", entry: nil, accent: .american, model: .loading)
    #expect(state.mainSenses.isEmpty)
    #expect(state.showsSentenceSection)

    // The part of speech comes with the whole card, after the definition.
    state.show(definition: "经营；管理", contextTranslation: nil)
    #expect(state.mainSenses == [CardState.Sense(partOfSpeech: "", gloss: "经营；管理")])
    state.show(card)
    #expect(state.mainSenses == [CardState.Sense(partOfSpeech: "verb", gloss: "经营；管理")])
    // Shown once, under the title; the sentence section keeps the sentence and its translation.
    #expect(state.sentenceMeaning == nil)
    #expect(state.showsSentenceSection)
  }

  @Test func aTypedTermWithoutTheDictionaryHasNoSentenceSection() {
    var state = CardState(
      term: "ran", context: nil, entry: nil, accent: .american, model: .loading)
    var typed = card
    typed.contextTranslation = ""
    state.show(typed)
    #expect(state.mainSenses.map(\.gloss) == ["经营；管理"])
    #expect(!state.showsSentenceSection)
  }

  /// A part of speech sits on a chip at least as wide as the mockup's, wider for a long label.
  @Test func thePartOfSpeechChipsShareOneWidth() {
    #expect(CardLayout.chipWidth([]) == 0)
    #expect(CardLayout.chipWidth(["", ""]) == 0)
    #expect(CardLayout.chipWidth(["verb", "noun"]) == CardLayout.minimumChipWidth)
    let phrasal = CardLayout.chipWidth(["verb", "phrasal verb"])
    #expect(phrasal > CardLayout.minimumChipWidth)
    #expect(phrasal == CardLayout.chipWidth(["phrasal verb"]))
  }

  /// The collocations' phrases share a column as wide as the widest, up to a cap past which a
  /// phrase wraps.
  @Test func thePhraseColumnFitsTheWidestPhraseUpToACap() {
    #expect(CardLayout.phraseWidth([]) == 0)
    let short = CardLayout.phraseWidth(["run a business", "run up"])
    #expect(short == CardLayout.phraseWidth(["run a business"]))
    #expect(short > 40)
    #expect(short < CardLayout.maximumPhraseWidth)
    let long = CardLayout.phraseWidth([String(repeating: "run a business ", count: 6)])
    #expect(long == CardLayout.maximumPhraseWidth)
  }

  /// The looked-up word is marked in its sentence as a whole word, in any case; not inside
  /// another word.
  @Test func theTermIsFoundAsAWholeWordInItsSentence() {
    func marked(_ term: String, _ sentence: String) -> String? {
      CardLayout.termRange(term, in: sentence).map { String(sentence[$0]) }
    }
    #expect(marked("ran", "She ran a small bakery.") == "ran")
    #expect(marked("ran", "Oranges ran out; Ran said so.") == "ran")
    #expect(marked("RAN", "She ran.") == "ran")
    #expect(marked("took off", "The plane took off late.") == "took off")
    #expect(marked("ran", "Oranges are orange.") == nil)
    #expect(marked("ran", "") == nil)
    #expect(marked("", "She ran.") == nil)
  }

  @Test func onlyCommonWordsGetTheGreenBand() {
    #expect(FrequencyBand.common.tone == .success)
    #expect(FrequencyBand.moderate.tone == .neutral)
    #expect(FrequencyBand.rare.tone == .neutral)
  }

  @Test func thePartOfSpeechColumnFitsTheWidestLabel() {
    #expect(CardLayout.partOfSpeechWidth([]) == 0)
    #expect(CardLayout.partOfSpeechWidth(["", ""]) == 0)
    let verb = CardLayout.partOfSpeechWidth(["verb", "verb"])
    #expect(verb > 6)
    #expect(verb < 20)
    let adjective = CardLayout.partOfSpeechWidth(["verb", "adjective"])
    #expect(adjective > verb)
    #expect(adjective == CardLayout.partOfSpeechWidth(["adjective"]))
  }
}

struct NoticeKindTests {
  /// A selection with nothing to look up is a fact, not a problem: it gets the neutral disc.
  @Test func nothingToLookUpIsInformation() {
    #expect(CardStrings.nothingToLookUp.kind == .information)
    #expect(PanelNotice(title: "Failed").kind == .problem)
  }
}
