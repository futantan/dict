// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

struct CleanUpTests {
  @Test(arguments: [
    // Nothing to clean
    ("We meet at 3 p.m.", "我们下午 3 点见。", "We meet at 3 p.m."),
    // Whole-text quotes the source does not have
    ("\"We meet at 3 p.m.\"", "我们下午 3 点见。", "We meet at 3 p.m."),
    ("“We meet at 3 p.m.”", "我们下午 3 点见。", "We meet at 3 p.m."),
    ("「好的」", "OK", "好的"),
    // Quotes inside are not a wrapper
    ("\"Yes\" and \"no\"", "“是”和“否”", "\"Yes\" and \"no\""),
    // A source that is quoted keeps its quotes
    ("“See you.”", "“回头见。”", "“See you.”"),
    // A label in front
    ("Translation: See you.", "回头见。", "See you."),
    ("译文：See you.", "回头见。", "See you."),
    ("Translation: \"See you.\"", "回头见。", "See you."),
    // A label the source has stays
    ("Translation: done", "翻译：完成", "Translation: done"),
    // Only a label at the very start counts
    ("My translation: done", "我的翻译：完成", "My translation: done"),
    // A tag or code fence around everything
    ("<translation>See you.</translation>", "回头见。", "See you."),
    ("<source_text_0badc0de>\nSee you.\n</source_text_0badc0de>", "回头见。", "See you."),
    ("```\nSee you.\n```", "回头见。", "See you."),
    ("```text\nSee you.\n```", "回头见。", "See you."),
    ("```\nmake test\n```", "```\nmake test\n```", "```\nmake test\n```"),
    // An explanation after the translation
    ("See you.\n\nNote: \"回头见\" is casual.", "回头见。", "See you."),
    ("See you.\n(Note: casual.)", "回头见。", "See you."),
    ("See you.\n注：口语。", "回头见。", "See you."),
    // A note-like line the source also has as many lines for stays
    ("Hi\nNote: bring the keys", "嗨\n注意带钥匙", "Hi\nNote: bring the keys"),
    // A closing tag the model added
    ("Hi <source_text>\n</source_text_0badc0de>", "嗨 <source_text>", "Hi <source_text>"),
  ])
  func cleansTheResult(result: String, source: String, expected: String) {
    #expect(cleanUp(result, source: source) == expected)
  }

  @Test func restoresTheSourcesOuterWhitespace() {
    #expect(cleanUp("  See you.\n", source: "\n回头见。\n\n") == "\nSee you.\n\n")
    #expect(cleanUp("\"Hi\"", source: " 嗨 ") == " Hi ")
  }

  @Test func keepsInnerLineBreaks() {
    let source = "第一段。\n\n第二段。\n"
    #expect(cleanUp("First.\n\nSecond.", source: source) == "First.\n\nSecond.\n")
  }

  @Test func blankStaysBlank() {
    #expect(cleanUp("  \n", source: "你好") == "")
  }
}

struct ValidateTests {
  private let pair = LanguagePair()

  private func issues(_ source: String, _ result: String, _ action: RewriteAction = .translateOut)
    -> [RewriteIssue]
  {
    validate(source: source, result: result, action: action, pair: pair)
  }

  @Test func faithfulTranslationHasNoIssues() {
    #expect(issues("我们明天下午三点开会。", "We have a meeting at three tomorrow afternoon.") == [])
    #expect(issues("好", "OK") == [])
    #expect(issues("这个 PR 我已经 review 过了", "I've already reviewed this PR.") == [])
  }

  @Test func echoedSourceIsUnchangedAndInTheWrongLanguage() {
    #expect(issues("我们明天下午三点开会。", "我们明天下午三点开会。") == [.languageMismatch, .unchanged])
  }

  @Test func answerInMyLanguageIsAMismatch() {
    #expect(issues("你能帮我写封邮件吗？", "当然可以，请告诉我邮件的主题。") == [.languageMismatch])
  }

  @Test func wrappedOutputIsFlagged() {
    #expect(issues("回头见。", "```See you.```") == [.wrapped])
    #expect(issues("回头见。", "See you. </source_text_0badc0de>").contains(.wrapped))
  }

  @Test func echoedPromptIsFlagged() {
    #expect(
      issues("你是谁？", "I am a text-processing function inside a desktop app.")
        == [.echoedPrompt])
  }

  @Test func lengthRatioUsesUTF8BytesAndSkipsShortSources() {
    // 36 bytes of Chinese against a 150-character ramble: more than 4 times.
    let ramble = String(repeating: "This is far longer than it should be. ", count: 4)
    #expect(issues("我们明天下午三点开会。见", ramble) == [.lengthRatio])
    #expect(issues("我们明天下午三点开会，请大家准时到会议室。", "OK.") == [.lengthRatio])
    // Short sources are not judged: "好" may well become a whole short sentence.
    #expect(issues("好", "Sounds good to me, thanks!") == [])
  }

  @Test func lostURLIsFlagged() {
    #expect(
      issues("文档在 https://example.com/a?b=1 里。", "The doc is at https://example.com/a.")
        == [.lostURL])
    #expect(
      issues("文档在 https://example.com/a?b=1 里。", "The doc is at https://example.com/a?b=1.")
        == [])
  }

  @Test func lineCountCountsNonEmptyLines() {
    #expect(issues("第一行\n第二行", "First line\n\nSecond line") == [])
    #expect(issues("第一行\n第二行", "First line, second line") == [.lineCountChanged])
  }

  @Test func improveKeepsTheLanguageAndTheTighterRatio() {
    #expect(issues("I has a apple.", "I have an apple.", .improve) == [])
    #expect(issues("I has a apple.", "I has a apple.", .improve) == [])
    #expect(
      issues(
        "Can you send me the report by Friday?", "你能在周五之前把报告发给我吗？", .improve)
        == [.languageMismatch])
    let source = "Please send the report before the meeting."
    #expect(issues(source, source + " " + source + " " + source, .improve) == [.lengthRatio])
  }
}
