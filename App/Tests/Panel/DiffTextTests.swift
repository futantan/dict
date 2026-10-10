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

  /// The removed and inserted words read at 4.5:1 or more on the panel's fill in either
  /// appearance, the insertions on their tint; the bare system green on the light fill is
  /// about 2:1.
  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theChangesAreLegibleOnTheFill(_ name: NSAppearance.Name) throws {
    let appearance = try #require(NSAppearance(named: name))
    let tint = NSColor.systemGreen.withAlphaComponent(0.14)
    for (color, behind) in [(DiffColor.removed, nil), (DiffColor.inserted, tint)] {
      let ratio = Self.contrast(color, on: behind, in: appearance)
      #expect(ratio >= 4.5, "\(color) in \(name.rawValue): \(ratio)")
    }
  }

  /// The WCAG contrast of `color` on the opaque window background, under `tint` if any.
  private static func contrast(
    _ color: NSColor, on tint: NSColor?, in appearance: NSAppearance
  ) -> Double {
    var ratio = 0.0
    appearance.performAsCurrentDrawingAppearance {
      func rgba(_ color: NSColor) -> [Double] {
        guard let c = color.usingColorSpace(.sRGB) else { return [0, 0, 0, 1] }
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map(
          Double.init)
      }
      func luminance(_ c: [Double]) -> Double {
        let l = c.prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
      }
      var back = rgba(.windowBackgroundColor)
      if let tint {
        let over = rgba(tint)
        back = (0..<3).map { back[$0] * (1 - over[3]) + over[$0] * over[3] }
      }
      let (a, b) = (luminance(rgba(color)), luminance(back))
      ratio = (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    return ratio
  }
}
