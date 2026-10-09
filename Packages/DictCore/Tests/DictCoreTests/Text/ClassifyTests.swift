// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import DictCore

/// Hand-written selections for each rule of architecture 5.1, in rule order.
struct ClassifyTests {
  @Test(arguments: [
    // Rule 2: nothing to look up.
    "",
    "   ",
    "\n\t\u{3000}",
    "...",
    "—",
    "「」",
    "😀",
    "👍🏽 🎉",
    "2024",
    "3.14",
    "$3.50",
    "+86 138 0000 0000",
    "42%",
    "(1, 2, 3)",
    "https://example.com/path?q=1",
    "  https://example.com/a.  ",
    "www.apple.com",
    "example.com",
    "x.ai",
    "github.com/foo/bar",
    "foo@bar.com",
    "<foo@bar.com>",
    "mailto:a@b.co",
  ])
  func none(_ text: String) {
    #expect(classify(text) == .none)
  }

  @Test(arguments: [
    // Rule 3: Latin and Hangul without inner whitespace.
    "hello",
    "Hello",
    "  serendipity\n",
    "hello,",
    "(hello)",
    "“hello”",
    "- hello",
    "#hashtag",
    "Hello.",
    "Thanks!",
    "Really?",
    "well-known",
    "state-of-the-art",
    "don't",
    "O'Brien",
    "rock'n'roll",
    "e.g.",
    "U.S.",
    "Ph.D.",
    "node.js",
    "README.md",
    "COVID-19",
    "2nd",
    "4K",
    "1990s",
    "café",
    "naïve",
    "Straße",
    "Ｈｅｌｌｏ",
    "😀hello",
    "안녕하세요",
    "привет",
    // Rule 6, one token.
    "机器",
    "一石二鸟",
    "人工智能",
    "タワー",
  ])
  func word(_ text: String) {
    #expect(classify(text) == .word)
  }

  @Test(arguments: [
    // Rule 5: 2 to 6 whitespace-separated words without a sentence end.
    "look up",
    "Thank you",
    "Getting Started",
    "take it with a grain",
    "in spite of",
    "100 km",
    "He left.”",
    "state of the art",
    "  look   up  ",
    "look\nup",
    "one two three four five six",
    "감사 합니다",
    // Rule 6: 2 to 3 tokens and at most 7 characters.
    "机器学习",
    "你好吗",
    "人工智能技术",
    "東京タワー",
    "画蛇添足的故事",
  ])
  func phrase(_ text: String) {
    #expect(classify(text) == .phrase)
  }

  @Test(arguments: [
    // Rule 4: the raw text ends a sentence.
    "Thank you.",
    "Is it done?",
    "Stop it!",
    "Wait for it…",
    "The quick brown fox jumps over the lazy dog.",
    "The quick brown fox jumps over the lazy dog.\nIt was a bright cold day.",
    "你好吗？",
    "好的。",
    "我在学英语！",
    "Python编程很有趣。",
    // Rule 5: more than 6 words.
    "one two three four five six seven",
    "a bright cold day in April with clocks striking",
    // Rule 6: more tokens or characters.
    "我喜欢吃苹果",
    "我在学英语，你呢",
    "这个 PR 我已经 review 过了",
    "ありがとうございます",
    "Python编程",
  ])
  func passage(_ text: String) {
    #expect(classify(text) == .passage)
  }
}
