// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

private func pair(_ mine: String, _ learning: String) -> LanguagePair {
  LanguagePair(
    mine: Locale.Language(identifier: mine), learning: Locale.Language(identifier: learning))
}

/// Same-script rows only use inputs whose recognizer confidence is far from the 0.8 threshold,
/// so the table does not flip when the system model changes.
struct ResolveDirectionTests {
  /// Default pair: a Simplified Chinese speaker learning English (different scripts).
  @Test(arguments: [
    // Chinese
    ("你好", Direction.intoLearning),
    ("这是一个关于国际经济发展的报告。", .intoLearning),
    ("我", .intoLearning),
    ("“你好”", .intoLearning),
    ("這是繁體中文。", .intoLearning),
    // English
    ("The cat is on the table.", .intoMine),
    ("cat", .intoMine),
    ("I", .intoMine),
    ("e.g.", .intoMine),
    ("ＨＥＬＬＯ", .intoMine),
    // Mixed: at least a third of the letters in my script translates into English
    ("这个 PR 我已经 review 过了", .intoLearning),
    ("我用 Python 写", .intoLearning),
    ("中ab", .intoLearning),
    ("中abc", .intoMine),
    ("Please review 这个", .intoMine),
    ("Python编程", .intoMine),
    // A third language falls back to translating into mine
    ("Je voudrais un café, s'il vous plaît.", .intoMine),
    ("Guten Morgen", .intoMine),
    ("これはペンです", .intoMine),
    ("안녕하세요", .intoMine),
    ("Привет, как дела?", .intoMine),
    // Emoji, digits and punctuation do not count as letters
    ("你好😀", .intoLearning),
    ("ok 👍", .intoMine),
    ("2026 年", .intoLearning),
    ("version 2026", .intoMine),
    // Nothing to decide on
    ("", .undecided),
    ("   \n\t", .undecided),
    ("...", .undecided),
    ("，。！？", .undecided),
    ("123", .undecided),
    ("😀", .undecided),
    ("👍🏽🎉", .undecided),
  ])
  func chineseLearningEnglish(text: String, expected: Direction) {
    #expect(resolveDirection(text, pair: LanguagePair()) == expected)
  }

  /// The reverse pair: an English speaker learning Chinese.
  @Test(arguments: [
    ("你好", Direction.intoMine),
    ("这是一个关于国际经济发展的报告。", .intoMine),
    ("Hello", .intoLearning),
    ("The cat is on the table.", .intoLearning),
    ("Привет", .intoMine),
    ("...", .undecided),
  ])
  func englishLearningChinese(text: String, expected: Direction) {
    #expect(resolveDirection(text, pair: pair("en", "zh-Hans")) == expected)
  }

  /// A Spanish speaker learning English: same script, decided by the recognizer.
  @Test(arguments: [
    ("El gato está en la mesa.", Direction.intoLearning),
    ("¿Puedes traducir esto al francés?", .intoLearning),
    ("Hola, ¿cómo estás?", .intoLearning),
    ("buenos días", .intoLearning),
    ("The cat is on the table.", .intoMine),
    ("Can you translate this into French for me?", .intoMine),
    ("Hello, how are you?", .intoMine),
    // Low confidence: single words and a third language in the same script
    ("hotel", .undecided),
    ("Je voudrais un café, s'il vous plaît.", .undecided),
    // A third language in another script still falls back to mine
    ("你好", .intoMine),
    ("Привет, как дела?", .intoMine),
    ("", .undecided),
    ("😀", .undecided),
  ])
  func spanishLearningEnglish(text: String, expected: Direction) {
    #expect(resolveDirection(text, pair: pair("es", "en")) == expected)
  }

  /// Simplified and Traditional Chinese share the Han script, so the recognizer decides.
  @Test(arguments: [
    ("这是一个关于国际经济发展的报告。", Direction.intoLearning),
    ("這是一個關於國際經濟發展的報告。", .intoMine),
  ])
  func simplifiedLearningTraditionalChinese(text: String, expected: Direction) {
    #expect(resolveDirection(text, pair: pair("zh-Hans", "zh-Hant")) == expected)
  }

  /// Two variants of one language cannot be told apart.
  @Test(arguments: ["colour", "The cat is on the table.", "..."])
  func sameLanguageIsUndecided(text: String) {
    #expect(resolveDirection(text, pair: pair("en-US", "en-GB")) == .undecided)
  }

  @Test(arguments: [
    (pair("ja", "en"), "これは日本語の文章です", Direction.intoLearning),
    (pair("ja", "en"), "日本語", .intoLearning),
    (pair("ja", "en"), "Hello", .intoMine),
    (pair("ko", "en"), "안녕하세요", .intoLearning),
    (pair("ko", "en"), "Hello", .intoMine),
    (pair("ru", "en"), "Привет, как дела?", .intoLearning),
    (pair("ru", "en"), "Hello", .intoMine),
    (pair("en", "ru"), "Привет", .intoMine),
    (pair("en", "ru"), "Hello", .intoLearning),
  ])
  func otherScripts(pair: LanguagePair, text: String, expected: Direction) {
    #expect(resolveDirection(text, pair: pair) == expected)
  }
}
