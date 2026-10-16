// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Testing

@testable import DictApp

/// The tokens and accent colour the windows use besides the panel's.
@MainActor
struct AppThemeTests {
  /// Native controls take the app's accent from the asset catalog, which must stay the
  /// panel's accent fill in both appearances.
  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theAccentColorIsTheAccentFill(_ name: NSAppearance.Name) throws {
    let appearance = try #require(NSAppearance(named: name))
    let accent = try #require(NSColor(named: "AccentColor"))
    let catalog = Contrast.rgba(accent, in: appearance)
    let token = Contrast.rgba(Palette.accentFill, in: appearance)
    for (a, b) in zip(catalog, token) {
      #expect(abs(a - b) < 0.005, "\(name.rawValue): \(catalog) vs \(token)")
    }
  }

  /// A failure reads at 4.5:1 or more on the panel and on the window background.
  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theFailureColorIsLegible(_ name: NSAppearance.Name) throws {
    let appearance = try #require(NSAppearance(named: name))
    for background in [Palette.panelFill, .windowBackgroundColor, .controlBackgroundColor] {
      let ratio = Contrast.ratio(Palette.failure, on: background, in: appearance)
      #expect(ratio >= 4.5, "\(name.rawValue) on \(background): \(ratio)")
    }
  }
}
