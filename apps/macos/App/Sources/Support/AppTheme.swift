// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Tokens the windows need beyond the panel's (`Palette`, Design/option-a/README.md). The
/// app's accent colour itself is the asset catalog's `AccentColor`, set to `accentFill`, so
/// native controls follow it.
extension Palette {
  /// A failed check or a rejected shortcut: an icon and short text on the window
  /// background. The panel shows failures in the warning tone; Settings tells them apart.
  static let failure = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(srgbRed: 1, green: 0x7B / 255, blue: 0x72 / 255, alpha: 1)
      : NSColor(srgbRed: 0xC4 / 255, green: 0x27 / 255, blue: 0x1F / 255, alpha: 1)
  }
}

extension Size {
  /// The toast's height on one line, and the tinted disc behind its icon.
  static let toast: CGFloat = 40
  static let toastDisc: CGFloat = 24
  static let toastSymbol: CGFloat = 13
  /// The widest the toast's message gets before it wraps.
  static let toastText: CGFloat = 400
}
