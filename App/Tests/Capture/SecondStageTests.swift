// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing

@testable import DictApp

struct SelectionBoundsTests {
  /// A 1440×900 primary screen and a 1920×1080 screen to its right, in Cocoa coordinates.
  let screens = [
    CGRect(x: 0, y: 0, width: 1440, height: 900),
    CGRect(x: 1440, y: 0, width: 1920, height: 1080),
  ]

  @Test func flipsFromTopLeftToBottomLeftOrigin() {
    let rect = selectionBounds(
      fromAccessibility: CGRect(x: 100, y: 200, width: 80, height: 20), screens: screens)
    #expect(rect == CGRect(x: 100, y: 680, width: 80, height: 20))
  }

  @Test func usesThePrimaryScreenHeightOnOtherScreens() {
    let rect = selectionBounds(
      fromAccessibility: CGRect(x: 2000, y: 100, width: 50, height: 18), screens: screens)
    #expect(rect == CGRect(x: 2000, y: 782, width: 50, height: 18))
  }

  @Test func rejectsEmptyRects() {
    #expect(selectionBounds(fromAccessibility: .zero, screens: screens) == nil)
    #expect(
      selectionBounds(
        fromAccessibility: CGRect(x: 10, y: 10, width: 0, height: 20), screens: screens)
        == nil)
  }

  @Test func rejectsRectsOffEveryScreen() {
    let rect = CGRect(x: -5000, y: 100, width: 50, height: 18)
    #expect(selectionBounds(fromAccessibility: rect, screens: screens) == nil)
  }

  @Test func rejectsRectsTallerThanFiveLines() {
    let tall = CGRect(x: 10, y: 10, width: 400, height: 600)
    #expect(selectionBounds(fromAccessibility: tall, screens: screens) == nil)
  }

  @Test func rejectsEverythingWithoutScreens() {
    let rect = CGRect(x: 10, y: 10, width: 50, height: 18)
    #expect(selectionBounds(fromAccessibility: rect, screens: []) == nil)
  }
}

/// The sentence rules are DictCore's (`SentenceLocatorTests`); these check the UTF-16 adapter.
struct ContextLocatorTests {
  @Test func convertsUTF16OffsetsAfterEmojiAndChinese() throws {
    let paragraph = "你好，世界。🙂 我在学英语。Then a test word."
    let location = NSRange(try #require(paragraph.range(of: "学英语")), in: paragraph)
    let context = try #require(contextSentence(in: paragraph, selection: location))
    #expect(context.sentence == "🙂 我在学英语。")
    #expect(context.sentence[context.termRange] == "学英语")
  }

  @Test func selectionSpanningSentencesHasNoContext() throws {
    let paragraph = "One two. Three four."
    let location = NSRange(try #require(paragraph.range(of: "two. Three")), in: paragraph)
    #expect(contextSentence(in: paragraph, selection: location) == nil)
  }

  @Test func emptyOrOutOfRangeSelectionHasNoContext() {
    #expect(contextSentence(in: "Hello.", selection: NSRange(location: 2, length: 0)) == nil)
    #expect(contextSentence(in: "Hello.", selection: NSRange(location: 4, length: 9)) == nil)
  }

  @Test func windowAroundSelectionIsClampedToTheText() {
    #expect(
      contextWindow(selection: NSRange(location: 10, length: 5), total: 2000, radius: 500)
        == NSRange(location: 0, length: 515))
    #expect(
      contextWindow(selection: NSRange(location: 1000, length: 5), total: 1200, radius: 500)
        == NSRange(location: 500, length: 700))
  }
}

/// Electron's paragraph markers run past the editor (VS Code: the tab title, U+FFFC and the
/// Chat panel title), so the paragraph is clipped to the focused element's value.
struct ElementClipTests {
  struct Case: Sendable, CustomTestStringConvertible {
    let paragraph: String
    let term: String
    /// The focused element's value, or nil when it has none.
    let value: String?
    /// The selection's range in `value`, when the element reports one.
    var valueRange: NSRange?
    let sentence: String

    var testDescription: String { "\(term) in \(paragraph.debugDescription)" }
  }

  static let sentence = "The quick brown fox jumps over the lazy dog."
  /// The paragraph VS Code's markers returned in `make matrix`.
  static let vsCodeParagraph = "sample.txt\u{FFFC}\u{FFFC}\(sentence)Chat"

  static let cases: [Case] = [
    Case(paragraph: vsCodeParagraph, term: "quick brown fox", value: sentence, sentence: sentence),
    Case(
      paragraph: vsCodeParagraph, term: sentence, value: sentence,
      valueRange: NSRange(location: 0, length: sentence.utf16.count), sentence: sentence),
    Case(
      paragraph: vsCodeParagraph, term: "quick brown fox", value: sentence,
      valueRange: NSRange(location: 4, length: 15), sentence: sentence),
    // A stale range falls back to finding the text in the value.
    Case(
      paragraph: vsCodeParagraph, term: "quick brown fox", value: sentence,
      valueRange: NSRange(location: 0, length: 15), sentence: sentence),
    // The value holds more lines than the paragraph: the clip stops where they differ.
    Case(
      paragraph: "Tab\u{FFFC}\(sentence)Panel", term: "lazy dog",
      value: "First line.\n\(sentence)\nLast line.", sentence: sentence),
    // No value, or a value without the selection: the paragraph is kept as it is.
    Case(paragraph: "One two. Three four.", term: "Three", value: nil, sentence: "Three four."),
    Case(
      paragraph: "One two. Three four.", term: "Three", value: "Unrelated text.",
      sentence: "Three four."),
    // The text twice in the value and no range: no guessing, the paragraph is kept.
    Case(paragraph: "A cat sat. It ran.", term: "cat", value: "cat cat", sentence: "A cat sat."),
  ]

  @Test(arguments: cases)
  func clipsTheParagraphToTheElement(_ testCase: Case) throws {
    let paragraph = testCase.paragraph
    let selection = NSRange(try #require(paragraph.range(of: testCase.term)), in: paragraph)
    let (clipped, local) = clip(
      paragraph: paragraph, selection: selection, to: testCase.value,
      valueRange: testCase.valueRange)
    let context = try #require(contextSentence(in: clipped, selection: local))
    #expect(context.sentence == testCase.sentence)
    #expect(context.sentence[context.termRange] == testCase.term)
  }
}
