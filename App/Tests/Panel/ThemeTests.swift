// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Testing

@testable import DictApp

@MainActor
struct ThemeTests {
  /// The text that has to be read reads at 4.5:1 or more on what it lies on, in either
  /// appearance; a translucent tint is measured over the panel's fill.
  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theTextIsLegible(_ name: NSAppearance.Name) throws {
    let appearance = try #require(NSAppearance(named: name))
    let pairs: [(String, NSColor, NSColor)] = [
      ("textPrimary", Palette.textPrimary, Palette.panelFill),
      ("textSecondary", Palette.textSecondary, Palette.panelFill),
      ("white on accentFill", .white, Palette.accentFill),
      ("accentOnTint", Palette.accentOnTint, Palette.accentTint),
      ("accentOnTint on block", Palette.accentOnTint, Palette.accentBlock),
      ("successOnTint", Palette.successOnTint, Palette.successTint),
      ("warningOnTint", Palette.warningOnTint, Palette.warningTint),
      ("neutralOnTint", Palette.neutralOnTint, Palette.neutralTint),
    ]
    for (label, text, background) in pairs {
      let ratio = Contrast.ratio(text, on: background, in: appearance)
      #expect(ratio >= 4.5, "\(label) in \(name.rawValue): \(ratio)")
    }
  }

  /// The panel's fill keeps following the appearance with its opacity applied.
  @Test func theBackingColorIsDynamic() throws {
    let light = try #require(NSAppearance(named: .aqua))
    let dark = try #require(NSAppearance(named: .darkAqua))
    let inLight = Contrast.rgba(PanelBacking.color, in: light)
    let inDark = Contrast.rgba(PanelBacking.color, in: dark)
    #expect(inLight[0] > 0.9)
    #expect(inDark[0] < 0.2)
    #expect(abs(inLight[3] - PanelBacking.opacity) < 0.001)
    #expect(abs(inDark[3] - PanelBacking.opacity) < 0.001)
  }
}

/// WCAG contrast of the palette's colours.
enum Contrast {
  /// The sRGB components of `color` resolved in `appearance`.
  @MainActor
  static func rgba(_ color: NSColor, in appearance: NSAppearance) -> [Double] {
    var components: [Double] = [0, 0, 0, 1]
    appearance.performAsCurrentDrawingAppearance {
      guard let c = color.usingColorSpace(.sRGB) else { return }
      components = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map(
        Double.init)
    }
    return components
  }

  /// The contrast of `color` on `background`, which, if translucent, lies on the panel's
  /// opaque fill.
  @MainActor
  static func ratio(_ color: NSColor, on background: NSColor, in appearance: NSAppearance)
    -> Double
  {
    func over(_ top: [Double], _ bottom: [Double]) -> [Double] {
      (0..<3).map { bottom[$0] * (1 - top[3]) + top[$0] * top[3] } + [1]
    }
    func luminance(_ c: [Double]) -> Double {
      let l = c.prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
      return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
    }
    let fill = rgba(Palette.panelFill, in: appearance)
    let back = over(rgba(background, in: appearance), fill)
    let front = over(rgba(color, in: appearance), back)
    let (a, b) = (luminance(front), luminance(back))
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
  }
}
