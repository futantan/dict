// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

/// The Write key translates out exactly when reading would translate into the learning
/// language, so the two keys agree on mixed text (architecture 5.3).
struct WriteActionTests {
  @Test(arguments: [
    // Mostly my language: translate out
    ("明天下午三点开会，别迟到。", Capability.translateOut),
    ("这个 PR 我已经 review 过了", .translateOut),
    ("我用 Python 写", .translateOut),
    ("2026 年", .translateOut),
    ("這是繁體中文。", .translateOut),
    // The learning language, or too little of my script: proofread
    ("Their going to the park tomorow.", .proofread),
    ("Please review 这个", .proofread),
    ("Python编程", .proofread),
    // A third language is proofread as it is
    ("Je voudrais un café.", .proofread),
    // Nothing to decide on: proofread, which never changes the language
    ("", .proofread),
    ("123", .proofread),
    ("👍", .proofread),
  ])
  func chineseLearningEnglish(text: String, expected: Capability) {
    #expect(writeAction(for: text, pair: LanguagePair()) == expected)
  }

  @Test func sameScriptPairFollowsTheRecognizer() {
    let pair = LanguagePair(
      mine: Locale.Language(identifier: "es"), learning: Locale.Language(identifier: "en"))
    #expect(
      writeAction(for: "Mañana tenemos una reunión muy importante con el equipo.", pair: pair)
        == .translateOut)
    #expect(
      writeAction(for: "Tomorrow we have a very important meeting with the team.", pair: pair)
        == .proofread)
  }
}
