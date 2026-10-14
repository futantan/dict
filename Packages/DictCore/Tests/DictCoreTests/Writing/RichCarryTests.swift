// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

// Formatting with keys of the tests' own: `carryAttributes` compares values, never reads them.
private let boldKey = NSAttributedString.Key("test.bold")
private let italicKey = NSAttributedString.Key("test.italic")
private let colorKey = NSAttributedString.Key("test.color")
private let docs = "https://example.com/docs"
private let L = "L=\(docs)"

/// An attributed string from (text, "B,I,L=<url>,C=<hex>") pieces.
private func make(_ pieces: [(String, String)]) -> NSAttributedString {
  let result = NSMutableAttributedString()
  for (text, spec) in pieces {
    var attributes: [NSAttributedString.Key: Any] = [:]
    for flag in spec.split(separator: ",").map(String.init) {
      switch flag {
      case "B": attributes[boldKey] = true
      case "I": attributes[italicKey] = true
      case _ where flag.hasPrefix("L="):
        attributes[linkKey] = URL(string: String(flag.dropFirst(2)))
      case _ where flag.hasPrefix("C="): attributes[colorKey] = String(flag.dropFirst(2))
      default: Issue.record("unknown flag \(flag)")
      }
    }
    result.append(NSAttributedString(string: text, attributes: attributes))
  }
  return result
}

private func runs(_ text: NSAttributedString) -> [StyledRun] {
  var runs: [StyledRun] = []
  text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
    let style = RunStyle(
      bold: attributes[boldKey] != nil, italic: attributes[italicKey] != nil,
      link: (attributes[linkKey] as? URL)?.absoluteString, color: attributes[colorKey] as? String)
    runs.append(StyledRun((text.string as NSString).substring(with: range), style))
  }
  return runs
}

private func described(_ pieces: [(String, String)]) -> String { describeRuns(runs(make(pieces))) }

private func spelling(_ wrong: String, _ right: String) -> Edit {
  Edit(kind: .spelling, wrong: wrong, right: right)
}

/// The source's formatting carried through the corrections the model made.
private func corrected(_ pieces: [(String, String)], _ edits: [Edit]) throws -> String? {
  let source = make(pieces)
  let applied = try applyEdits(edits, to: source.string).get()
  return carryAttributes(from: source, along: applied.segments).map { describeRuns(runs($0)) }
}

/// The source's formatting carried onto a rewrite, through the diff.
private func rewritten(_ pieces: [(String, String)], to text: String) -> String? {
  let source = make(pieces)
  return carryAttributes(from: source, along: textDiff(source.string, text)).map {
    describeRuns(runs($0))
  }
}

/// The cases of the rich-replace spike (`spikes/results/rich-replace.md`), and partial
/// acceptance and translation, which only the product has.
struct RichCarryTests {
  @Test func aBoldWordCorrectedStaysBold() throws {
    let result = try corrected(
      [("I has a ", ""), ("wrd", "B"), (" here.", "")],
      [spelling("has", "have"), spelling("wrd", "word")])
    #expect(result == described([("I have a ", ""), ("word", "B"), (" here.", "")]))
  }

  @Test func aWordCorrectedInsideALinkKeepsTheWholeLink() throws {
    let result = try corrected(
      [("See ", ""), ("the documantation page", L), (" now.", "")],
      [spelling("documantation", "documentation")])
    #expect(result == described([("See ", ""), ("the documentation page", L), (" now.", "")]))
  }

  @Test func anInsertionAtTheStartTakesTheNextCharacter() {
    let result = rewritten([("quick", "B"), (" fox jumps.", "")], to: "The quick fox jumps.")
    #expect(result == described([("The quick", "B"), (" fox jumps.", "")]))
  }

  @Test func anInsertionAtTheStartDoesNotExtendALinkItTouches() {
    let result = rewritten([("docs", L), (" are here.", "")], to: "The docs are here.")
    #expect(result == described([("The ", ""), ("docs", L), (" are here.", "")]))
  }

  /// The diff merges changes only whitespace apart, so one change spans both formats.
  @Test func aChangeAcrossFormatsWithAsManyWordsGoesWordByWord() throws {
    let result = try corrected(
      [("ths ", ""), ("wrd", "B"), (" is fine.", "")],
      [spelling("ths", "this"), spelling("wrd", "word")])
    #expect(result == described([("this ", ""), ("word", "B"), (" is fine.", "")]))
  }

  /// A known loss: two words joined into one keep only what both had.
  @Test func aChangeAcrossFormatsWithFewerWordsKeepsOnlyTheCommonFormat() throws {
    let result = try corrected(
      [("Do ", ""), ("some", ""), (" thing", "B"), (" now.", "")],
      [spelling("some thing", "something")])
    #expect(result == described([("Do something now.", "")]))
  }

  @Test func aChangeNextToAFormattedWordLeavesItAlone() throws {
    let result = try corrected(
      [("I want alot", ""), (" of", "I"), (" it.", "")], [spelling("alot", "a lot")])
    #expect(result == described([("I want a lot", ""), (" of", "I"), (" it.", "")]))
  }

  @Test func anInsertionRightAfterALinkDoesNotExtendIt() {
    let result = rewritten([("Read the ", ""), ("docs", L), (".", "")], to: "Read the docs today.")
    #expect(result == described([("Read the ", ""), ("docs", L), (" today.", "")]))
  }

  @Test func aRewriteOfMixedFormatsKeepsOnlyWhatAllOfItShares() {
    let result = rewritten(
      [("Ths ", ""), ("sentense", "B"), (" are ", ""), ("bad", "C=#cc0000"), (".", "")],
      to: "Rewritten from scratch entirely.")
    #expect(result == described([("Rewritten from scratch entirely.", "")]))
  }

  @Test func aRewriteOfUniformlyItalicTextStaysItalic() {
    let result = rewritten(
      [("Ths sentense are bad.", "I")], to: "Rewritten from scratch entirely.")
    #expect(result == described([("Rewritten from scratch entirely.", "I")]))
  }

  @Test func aDeletionDropsTextAndKeepsTheRest() {
    let result = rewritten([("This is is ", ""), ("bold", "B"), (".", "")], to: "This is bold.")
    #expect(result == described([("This is ", ""), ("bold", "B"), (".", "")]))
  }

  @Test func twoParagraphsKeepTheBreakAndTheItalic() throws {
    let result = try corrected(
      [("Para one wrng.\nPara ", ""), ("two", "I"), (" ok.", "")], [spelling("wrng", "wrong")])
    #expect(result == described([("Para one wrong.\nPara ", ""), ("two", "I"), (" ok.", "")]))
  }

  @Test func aColoredWordCorrectedKeepsItsColor() throws {
    let result = try corrected(
      [("Status: ", ""), ("faild", "C=#cc0000"), (".", "")], [spelling("faild", "failed")])
    #expect(result == described([("Status: ", ""), ("failed", "C=#cc0000"), (".", "")]))
  }

  @Test func aChineseCharacterInsideBoldStaysBold() throws {
    let result = try corrected(
      [("他", ""), ("在", "B"), ("去一次", "")], [Edit(kind: .wordForm, wrong: "在", right: "再")])
    #expect(result == described([("他", ""), ("再", "B"), ("去一次", "")]))
  }

  @Test func offsetsAfterEmojiAreUTF16() throws {
    let result = try corrected(
      [("😀 ok ", ""), ("wrd", "B"), (" 👍🏽 end", "")], [spelling("wrd", "word")])
    #expect(result == described([("😀 ok ", ""), ("word", "B"), (" 👍🏽 end", "")]))
  }

  @Test func segmentsThatDoNotSpellTheSourceGiveNil() {
    #expect(carryAttributes(from: make([("abc", "B")]), along: [.unchanged("abd")]) == nil)
  }

  // MARK: Partial acceptance (architecture 6.7)

  private let mixed: [(String, String)] = [
    ("Ths is a ", ""), ("bold wrd", "B"), (" and ", ""), ("a lnk", L), (".", ""),
  ]
  private let mixedEdits = [
    spelling("Ths", "This"), spelling("wrd", "word"), spelling("lnk", "link"),
  ]

  @Test func declinedChangesKeepTheSourceAndItsFormatting() throws {
    let source = make(mixed)
    let applied = try applyEdits(mixedEdits, to: source.string).get()
    #expect(applied.changeCount == 3)
    let onlyTheBoldWord = applied.accepting([1])
    let result = carryAttributes(from: source, along: onlyTheBoldWord.segments)
    #expect(result?.string == "Ths is a bold word and a lnk.")
    #expect(
      result.map { describeRuns(runs($0)) }
        == described([
          ("Ths is a ", ""), ("bold word", "B"), (" and ", ""), ("a lnk", L), (".", ""),
        ]))
  }

  @Test func everyChangeDeclinedGivesTheSourceBack() throws {
    let source = make(mixed)
    let applied = try applyEdits(mixedEdits, to: source.string).get()
    let result = carryAttributes(from: source, along: applied.accepting([]).segments)
    #expect(result.map { describeRuns(runs($0)) } == described(mixed))
  }

  @Test func everyChangeAcceptedCarriesEachFormat() throws {
    let result = try corrected(mixed, mixedEdits)
    #expect(
      result
        == described([
          ("This is a ", ""), ("bold word", "B"), (" and ", ""), ("a link", L), (".", ""),
        ]))
  }

  // MARK: Translation: one change for the whole text

  @Test func aTranslationOfUniformlyItalicTextStaysItalic() {
    let source = make([("我们明天开会。", "I")])
    let result = carryAttributes(
      from: source, along: [.changed(from: source.string, to: "We meet tomorrow.")])
    #expect(result.map { describeRuns(runs($0)) } == described([("We meet tomorrow.", "I")]))
  }

  @Test func aTranslationOfMixedFormatsKeepsOnlyTheCommonFormat() {
    let source = make([("我们", "C=#cc0000"), ("明天", "B,C=#cc0000"), ("开会。", "C=#cc0000")])
    let result = carryAttributes(
      from: source, along: [.changed(from: source.string, to: "We meet tomorrow.")])
    #expect(
      result.map { describeRuns(runs($0)) } == described([("We meet tomorrow.", "C=#cc0000")]))
  }
}

struct RichRunsTests {
  private let link = RunStyle(link: docs)

  @Test func aSingleLineStaysInline() {
    let html = semanticHTML([
      StyledRun("See "), StyledRun("the docs", RunStyle(bold: true, link: docs)),
      StyledRun(" & more", RunStyle(italic: true)),
    ])
    #expect(
      html
        == "<meta charset=\"utf-8\">See <a href=\"https://example.com/docs\"><b>the docs</b></a>"
        + "<i> &amp; more</i>")
  }

  @Test func paragraphsBecomeParagraphElementsAndAnEmptyOneABreak() {
    let html = semanticHTML([
      StyledRun("One "), StyledRun("bold", RunStyle(bold: true)), StyledRun("\n\nTwo."),
    ])
    #expect(html == "<meta charset=\"utf-8\"><p>One <b>bold</b></p><p><br></p><p>Two.</p>")
  }

  @Test func aLinkSpanningRunsIsOneAnchorAndDropsItsRenderedColor() {
    let html = semanticHTML([
      StyledRun("a ", RunStyle(link: docs, color: "#0000ee")),
      StyledRun("bold", RunStyle(bold: true, underline: true, link: docs, color: "#0000ee")),
      StyledRun(" red", RunStyle(color: "#cc0000")),
      StyledRun(" gone", RunStyle(underline: true, strike: true)),
    ])
    #expect(
      html
        == "<meta charset=\"utf-8\"><a href=\"https://example.com/docs\">a <b>bold</b></a>"
        + "<span style=\"color:#cc0000\"> red</span><u><s> gone</s></u>")
  }

  @Test func markupInTheTextIsEscaped() {
    #expect(
      semanticHTML([StyledRun("<b>\"x\" & y</b>")]).hasSuffix(
        "&lt;b&gt;&quot;x&quot; &amp; y&lt;/b&gt;"))
  }

  @Test func formattingIsAnyMarkOrMoreThanOneColor() {
    #expect(!carriesFormatting([StyledRun("plain")]))
    #expect(
      !carriesFormatting([
        StyledRun("theme ", RunStyle(color: "#bbbebf")),
        StyledRun("color", RunStyle(color: "#bbbebf")),
      ]))
    #expect(carriesFormatting([StyledRun("a "), StyledRun("red", RunStyle(color: "#cc0000"))]))
    #expect(carriesFormatting([StyledRun("all bold", RunStyle(bold: true))]))
    #expect(carriesFormatting([StyledRun("x", link)]))
    #expect(!carriesFormatting([StyledRun("x"), StyledRun("", RunStyle(bold: true))]))
  }

  @Test func describingMergesRunsOfTheSameStyle() {
    #expect(
      describeRuns([
        StyledRun("a"), StyledRun("b"), StyledRun("c\nd", RunStyle(bold: true, link: docs)),
      ]) == "[ab][c⏎d]{B,L=https://example.com/docs}")
  }
}
