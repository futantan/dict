// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

struct SentenceLocatorTests {
  struct Case: Sendable, CustomTestStringConvertible {
    let paragraph: String
    let term: String
    var occurrence = 0
    /// The expected sentence, or nil when there must be no context.
    let sentence: String?
    /// The expected highlighted text when it is not `term` itself.
    var highlighted: String?

    var testDescription: String { "\(term) in \(paragraph.debugDescription)" }
  }

  static let cases: [Case] = [
    // Plain sentences and trimming.
    Case(
      paragraph: "Hello world. This is the second sentence. The fox jumps.", term: "second",
      sentence: "This is the second sentence."),
    Case(paragraph: "Hello world.", term: "Hello", sentence: "Hello world."),
    Case(
      paragraph: "A single clause without an end", term: "clause",
      sentence: "A single clause without an end"),
    Case(
      paragraph: "First one.\n  Second has a word here.  \n", term: "word",
      sentence: "Second has a word here."),
    Case(
      paragraph: "A cat sat. Another cat ran.", term: "cat", occurrence: 1,
      sentence: "Another cat ran."),
    Case(paragraph: "It ends here. Done.", term: "Done.", sentence: "Done."),
    // Abbreviations, numbers and URLs do not end a sentence.
    Case(
      paragraph: "Use a tool, e.g. a hammer, to fix it. Then rest.", term: "hammer",
      sentence: "Use a tool, e.g. a hammer, to fix it."),
    Case(
      paragraph: "Dr. Smith went to Washington. He met Mr. Jones there.", term: "Smith",
      sentence: "Dr. Smith went to Washington."),
    Case(
      paragraph: "Dr. Smith went to Washington. He met Mr. Jones there.", term: "Jones",
      sentence: "He met Mr. Jones there."),
    Case(
      paragraph: "The U.S. economy grew. Prices rose.", term: "economy",
      sentence: "The U.S. economy grew."),
    Case(
      paragraph: "It costs $3.50 today. Version 2.0 shipped.", term: "shipped",
      sentence: "Version 2.0 shipped."),
    Case(
      paragraph: "See https://example.com/a.b for more. Next one.", term: "more",
      sentence: "See https://example.com/a.b for more."),
    Case(
      paragraph: "Wait... what happened? Nothing.", term: "happened",
      sentence: "Wait... what happened?"),
    // The paragraphs of the e2e context scenarios (Fixtures/E2E/scenarios.json).
    Case(
      paragraph: "The quick brown fox jumps over the lazy dog. It was a bright cold day in April.",
      term: "bright", sentence: "It was a bright cold day in April."),
    Case(
      paragraph:
        "The first paragraph ends here.\n\nDr. Smith opened the second one, e.g. with a joke. "
        + "It has two sentences.",
      term: "Smith", sentence: "Dr. Smith opened the second one, e.g. with a joke."),
    // Quotes and brackets stay with their sentence.
    Case(
      paragraph: "He said, \"Stop it.\" Then he left.", term: "Stop",
      sentence: "He said, \"Stop it.\""),
    Case(
      paragraph: "He said “Stop it.” Then he left.", term: "left",
      sentence: "Then he left."),
    Case(
      paragraph: "She asked (quietly) if it worked. It did!", term: "quietly",
      sentence: "She asked (quietly) if it worked."),
    // Line and paragraph breaks end a sentence, with or without punctuation.
    Case(
      paragraph: "Title Line\nThe body sentence follows here.", term: "body",
      sentence: "The body sentence follows here."),
    Case(
      paragraph: "Title Line\nThe body sentence follows here.", term: "Title",
      sentence: "Title Line"),
    Case(
      paragraph: "Para one.\n\nPara two is here. Last one.", term: "two",
      sentence: "Para two is here."),
    Case(paragraph: "Line one\u{2028}line two. Three.", term: "two", sentence: "line two."),
    // Chinese and Japanese punctuation, and UTF-16 offsets after emoji.
    Case(paragraph: "你好，世界。我在学英语！你呢？", term: "英语", sentence: "我在学英语！"),
    Case(
      paragraph: "我喜欢 Python 编程。This is mixed。下一句", term: "mixed",
      sentence: "This is mixed。"),
    Case(
      paragraph: "你好，世界。🙂 我在学英语。Then a test word.", term: "学英语",
      sentence: "🙂 我在学英语。"),
    Case(
      paragraph: "👨‍👩‍👧 family photo. The 👍🏽 word here.", term: "word",
      sentence: "The 👍🏽 word here."),
    Case(paragraph: "会議は明日です。午後三時に開始します。", term: "午後", sentence: "午後三時に開始します。"),
    // Whitespace around the selection is not part of the term.
    Case(
      paragraph: "One two. Three four.", term: " Three", sentence: "Three four.",
      highlighted: "Three"),
    Case(
      paragraph: "One two. Three four.", term: "two. ", sentence: "One two.",
      highlighted: "two."),
    // No context: the selection crosses a sentence or line, or is only whitespace.
    Case(paragraph: "One two. Three four.", term: "two. Three", sentence: nil),
    Case(paragraph: "Line one\nline two", term: "one\nline", sentence: nil),
    Case(paragraph: "One two. Three four.", term: " ", sentence: nil),
  ]

  @Test(arguments: cases)
  func locates(_ test: Case) throws {
    let selection = try #require(Self.range(of: test.term, in: test.paragraph, test.occurrence))
    let context = sentence(containing: selection, in: test.paragraph)
    #expect(context?.sentence == test.sentence)
    if let context {
      #expect(String(context.sentence[context.termRange]) == test.highlighted ?? test.term)
    }
  }

  @Test func emptySelectionHasNoContext() {
    let paragraph = "Hello world."
    let index = paragraph.index(paragraph.startIndex, offsetBy: 2)
    #expect(sentence(containing: index..<index, in: paragraph) == nil)
  }

  @Test func wholeParagraphSelection() throws {
    let paragraph = "  Just one sentence.  "
    let context = try #require(
      sentence(containing: paragraph.startIndex..<paragraph.endIndex, in: paragraph))
    #expect(context.sentence == "Just one sentence.")
    #expect(String(context.sentence[context.termRange]) == "Just one sentence.")
  }

  static func range(
    of term: String, in paragraph: String, _ occurrence: Int
  ) -> Range<String.Index>? {
    var searchStart = paragraph.startIndex
    var found: Range<String.Index>?
    for _ in 0...occurrence {
      found = paragraph.range(of: term, range: searchStart..<paragraph.endIndex)
      guard let hit = found else { return nil }
      searchStart = hit.upperBound
    }
    return found
  }
}
