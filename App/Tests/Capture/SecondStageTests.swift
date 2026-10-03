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

struct ContextLocatorTests {
  func locate(_ paragraph: String, _ term: String, occurrence: Int = 0) -> (String, String)? {
    var searchStart = paragraph.startIndex
    var found: Range<String.Index>?
    for _ in 0...occurrence {
      found = paragraph.range(of: term, range: searchStart..<paragraph.endIndex)
      guard let hit = found else { return nil }
      searchStart = hit.upperBound
    }
    guard let found else { return nil }
    let location = NSRange(found, in: paragraph)
    guard let context = contextSentence(in: paragraph, selection: location) else { return nil }
    return (context.sentence, String(context.sentence[context.termRange]))
  }

  @Test func findsTheSentenceAroundAWord() throws {
    let result = try #require(
      locate("Hello world. This is the second sentence. The fox jumps.", "second"))
    #expect(result.0 == "This is the second sentence.")
    #expect(result.1 == "second")
  }

  @Test func trimsSurroundingWhitespaceAndNewlines() throws {
    let result = try #require(locate("First one.\n  Second has a word here.  \n", "word"))
    #expect(result.0 == "Second has a word here.")
    #expect(result.1 == "word")
  }

  @Test func handlesUTF16OffsetsAfterEmojiAndChinese() throws {
    let result = try #require(locate("你好，世界。🙂 我在学英语。Then a test word.", "学英语"))
    #expect(result.0 == "🙂 我在学英语。")
    #expect(result.1 == "学英语")
  }

  @Test func usesTheRightOccurrence() throws {
    let result = try #require(locate("A cat sat. Another cat ran.", "cat", occurrence: 1))
    #expect(result.0 == "Another cat ran.")
  }

  @Test func selectionSpanningSentencesHasNoContext() {
    #expect(locate("One two. Three four.", "two. Three") == nil)
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
