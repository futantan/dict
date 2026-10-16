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
    #expect(gap[.dictTint] == nil)
    #expect(text.attributes(at: 0, effectiveRange: nil)[.strikethroughStyle] != nil)
    #expect(text.attributes(at: 6, effectiveRange: nil)[.dictTint] != nil)
  }

  @Test func pureInsertionsAndDeletionsGetNoGap() {
    #expect(
      diffText([.unchanged("a "), .changed(from: "", to: "big "), .unchanged("cat")]).string
        == "a big cat")
    #expect(
      diffText([.unchanged("a "), .changed(from: "big ", to: ""), .unchanged("cat")]).string
        == "a big cat")
  }

  /// The removed and inserted words read at 4.5:1 or more on the panel's fill in either
  /// appearance, the insertions on their tint; the bare system green on the light fill is
  /// about 2:1.
  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theChangesAreLegibleOnTheFill(_ name: NSAppearance.Name) throws {
    let appearance = try #require(NSAppearance(named: name))
    for (color, behind) in [
      (DiffColor.removed, Palette.panelFill), (DiffColor.inserted, DiffColor.insertedTint),
    ] {
      let ratio = Contrast.ratio(color, on: behind, in: appearance)
      #expect(ratio >= 4.5, "\(color) in \(name.rawValue): \(ratio)")
    }
  }
}
