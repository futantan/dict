// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import Testing

@testable import DictApp

@MainActor
struct DiffTextTests {
  /// A plain space keeps the struck-out words from running into their replacement; it is
  /// neither struck through nor highlighted.
  @Test func aReplacementIsSetApartFromWhatItReplaces() {
    let text = diffText([
      .changed(from: "Their", to: "They're"), .unchanged(" going"),
    ])
    #expect(text.string == "Their They're going")
    let gap = text.attributes(at: 5, effectiveRange: nil)
    #expect(gap[.strikethroughStyle] == nil)
    #expect(gap[.backgroundColor] == nil)
    #expect(text.attributes(at: 0, effectiveRange: nil)[.strikethroughStyle] != nil)
    #expect(text.attributes(at: 6, effectiveRange: nil)[.backgroundColor] != nil)
  }

  @Test func pureInsertionsAndDeletionsGetNoGap() {
    #expect(
      diffText([.unchanged("a "), .changed(from: "", to: "big "), .unchanged("cat")]).string
        == "a big cat")
    #expect(
      diffText([.unchanged("a "), .changed(from: "big ", to: ""), .unchanged("cat")]).string
        == "a big cat")
  }
}
