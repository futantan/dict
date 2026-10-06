// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import DictCore

struct ReadBackTests {
  private let original = "teh cat"
  private let result = "the cat"

  @Test func sameValueIsUnchanged() {
    let before = "I saw teh cat."
    #expect(
      replacementConfirmed(before: before, after: before, original: original, result: result)
        == .unchanged)
  }

  @Test func resultInPlaceOfTheOriginalIsConfirmed() {
    #expect(
      replacementConfirmed(
        before: "I saw teh cat.", after: "I saw the cat.", original: original, result: result)
        == .confirmed)
  }

  /// Chromium's value and offsets disagree, so the check counts occurrences, not positions.
  @Test func confirmationDoesNotDependOnPosition() {
    #expect(
      replacementConfirmed(
        before: "the cat. I saw teh cat.", after: "the cat. I saw the cat.", original: original,
        result: result) == .confirmed)
  }

  @Test func resultTwiceIsDuplicated() {
    #expect(
      replacementConfirmed(
        before: "I saw teh cat.", after: "I saw the catthe cat.", original: original,
        result: result) == .duplicated)
  }

  @Test func anyOtherChangeIsUnexpected() {
    #expect(
      replacementConfirmed(
        before: "I saw teh cat.", after: "I saw a dog.", original: original, result: result)
        == .changedUnexpectedly)
  }

  @Test func normalizesLineEndingsWhitespaceAndInvisibleCharacters() {
    #expect(
      replacementConfirmed(
        before: "a\r\nteh  cat\u{200B}", after: "a\nthe cat\u{FFFC}", original: "teh cat",
        result: "the cat") == .confirmed)
    #expect(
      replacementConfirmed(before: "e\u{301}", after: "\u{E9}", original: "x", result: "y")
        == .unchanged)
  }
}
