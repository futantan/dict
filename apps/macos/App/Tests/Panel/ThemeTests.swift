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
      ("textPrimary on highlight", Palette.textPrimary, Palette.highlight),
    ]
    for (label, text, background) in pairs {
      let ratio = Contrast.ratio(text, on: background, in: appearance)
      #expect(ratio >= 4.5, "\(label) in \(name.rawValue): \(ratio)")
    }
  }

  /// The parts of a control that show its state read at 3:1 or more on the panel's fill
  /// (non-text contrast), in either appearance: both the spinner's arc and its ring.
  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theSpinnerIsVisible(_ name: NSAppearance.Name) throws {
    let appearance = try #require(NSAppearance(named: name))
    for (label, color) in [("arc", Palette.accent), ("track", Palette.spinnerTrack)] {
      let ratio = Contrast.ratio(color, on: Palette.panelFill, in: appearance)
      #expect(ratio >= 3, "\(label) in \(name.rawValue): \(ratio)")
    }
    // The arc still stands out from the ring it turns on.
    let arc = Contrast.ratio(Palette.accent, on: Palette.spinnerTrack, in: appearance)
    #expect(arc >= 2, "arc on track in \(name.rawValue): \(arc)")
  }

  /// In dark the looked-up word's highlight stands 3:1 off the panel's fill, as a control's
  /// state does, while its text keeps 4.5:1 (`theTextIsLegible`); a translucent yellow over
  /// the dark fill turned a grey olive close to the fill.
  @Test func theDarkHighlightStandsOut() throws {
    let dark = try #require(NSAppearance(named: .darkAqua))
    let ratio = Contrast.ratio(Palette.highlight, on: Palette.panelFill, in: dark)
    #expect(ratio >= 3, "highlight on panelFill: \(ratio)")
  }

  /// The README's type table lists exactly the shared text styles, with their sizes and
  /// weights, so the design notes and the code cannot drift apart.
  @Test func theReadmeTypeTableMatchesTheTypography() throws {
    let styles: [String: TextStyle] = [
      "headword": Typography.headword, "result": Typography.result,
      "proofread": Typography.proofread, "title": Typography.title, "body": Typography.body,
      "callout": Typography.callout, "secondary": Typography.secondary,
      "button": Typography.button, "note": Typography.note, "pill": Typography.pill,
      "label": Typography.label, "caption": Typography.caption,
    ]
    let readme = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Design/option-a/README.md")
    let text = try String(contentsOf: readme, encoding: .utf8)
    let section =
      try #require(text.components(separatedBy: "## 字体").last)
      .components(separatedBy: "\n## ").first ?? ""
    let weights: [String: NSFont.Weight] = [
      "regular": .regular, "medium": .medium, "semibold": .semibold, "bold": .bold,
    ]
    var listed: Set<String> = []
    for line in section.split(separator: "\n") where line.hasPrefix("| `") {
      let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
      let name = cells[0].trimmingCharacters(in: CharacterSet(charactersIn: "`"))
      let parts = cells[1].components(separatedBy: " / ")
      let weight = parts[1].prefix { $0.isLetter }
      let style = try #require(styles[name], "\(name) is in the README but not in Typography")
      #expect(Double(parts[0]) == Double(style.size), "\(name)")
      #expect(weights[String(weight)] == style.weight, "\(name)")
      listed.insert(name)
    }
    #expect(listed == Set(styles.keys))
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
