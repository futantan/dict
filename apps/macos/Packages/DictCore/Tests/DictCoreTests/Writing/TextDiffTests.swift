// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import DictCore

struct TextDiffTests {
  @Test func sameTextIsOneUnchangedRun() {
    #expect(textDiff("All good.", "All good.") == [.unchanged("All good.")])
    #expect(textDiff("", "") == [])
  }

  @Test func wordsChangeWholeAndNeighboursMerge() {
    #expect(
      textDiff("I has went home", "I have gone home")
        == [.unchanged("I "), .changed(from: "has went", to: "have gone"), .unchanged(" home")])
  }

  /// Only a gap of pure whitespace joins two changes; a kept word keeps them apart.
  @Test func changesApartByAWordStaySeparate() {
    #expect(
      textDiff("has a went", "have a gone") == [
        .changed(from: "has", to: "have"), .unchanged(" a "), .changed(from: "went", to: "gone"),
      ])
  }

  @Test func insertionsAndDeletions() {
    #expect(
      textDiff("a cat", "a big cat") == [
        .unchanged("a "), .changed(from: "", to: "big "), .unchanged("cat"),
      ])
    #expect(
      textDiff("a big cat", "a cat") == [
        .unchanged("a "), .changed(from: "big ", to: ""), .unchanged("cat"),
      ])
  }

  /// Chinese has no spaces: each character is its own unit.
  @Test func chineseChangesByCharacter() {
    #expect(
      textDiff("我今天很高心", "我今天很高兴") == [.unchanged("我今天很高"), .changed(from: "心", to: "兴")])
  }

  @Test func aDiffThatIsTooLargeIsOneChange() {
    let old = Array(repeating: "a", count: 12_000).joined(separator: " ")
    let new = Array(repeating: "b", count: 12_000).joined(separator: " ")
    #expect(textDiff(old, new) == [.changed(from: old, to: new)])
  }
}
