// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// The panel's design tokens (Design/option-a/README.md). Views take every colour, font,
/// spacing and radius from here, so the panel changes its look in one place.

/// Colours with a light and a dark value, resolved in the appearance they are drawn in. A
/// translucent value lies on `panelFill`.
enum Palette {
  static let panelFill = dynamic(light: rgb(0xFBFBFD), dark: rgb(0x1E1E22))
  static let textPrimary = dynamic(light: rgb(0x1D1D1F), dark: rgb(0xF2F2F4))
  /// The original, notes and messages; 4.5:1 or more on the fill.
  static let textSecondary = dynamic(light: rgb(0x6E6E73), dark: rgb(0xA1A1A8))
  /// Placeholders and key caps only: nothing that has to be read.
  static let textTertiary = dynamic(light: rgb(0x8E8E93), dark: rgb(0x7C7C84))
  static let separator = dynamic(light: rgb(0xDEDEE3), dark: rgb(0x34343A))
  static let icon = dynamic(light: rgb(0x48484A), dark: rgb(0xC7C7CC))
  static let iconHover = dynamic(light: rgb(0x000000, 0.05), dark: rgb(0xFFFFFF, 0.08))
  /// The current change's underline, focus and links.
  static let accent = dynamic(light: rgb(0x5B3FD6), dark: rgb(0xA897FF))
  /// Under the primary button's white title.
  static let accentFill = dynamic(light: rgb(0x5B3FD6), dark: rgb(0x6D55E8))
  static let accentTint = dynamic(light: rgb(0xECE8FF), dark: rgb(0xA897FF, 0.18))
  static let accentOnTint = dynamic(light: rgb(0x5B3FD6), dark: rgb(0xC9BFFF))
  /// Under a block that stands out, lighter than a pill's tint.
  static let accentBlock = dynamic(light: rgb(0xF2F0FF), dark: rgb(0xA897FF, 0.10))
  static let successTint = dynamic(light: rgb(0xE3F4E8), dark: rgb(0x56D364, 0.16))
  static let successOnTint = dynamic(light: rgb(0x1F7A3A), dark: rgb(0x7EE08F))
  static let warningTint = dynamic(light: rgb(0xFFF0DE), dark: rgb(0xF5A524, 0.14))
  static let warningOnTint = dynamic(light: rgb(0xA34A00), dark: rgb(0xF5B54A))
  /// Under a secondary button, a note and a neutral pill, and the text on it; not in the
  /// README's table, taken from the mockups.
  static let neutralTint = dynamic(light: rgb(0xEFEFF2), dark: rgb(0xFFFFFF, 0.08))
  static let neutralOnTint = dynamic(light: rgb(0x545458), dark: rgb(0xB4B4BB))
  /// The looked-up word in its sentence.
  static let highlight = dynamic(light: rgb(0xFFE58F), dark: rgb(0xFFE58F, 0.35))

  private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    }
  }

  private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
      srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
  }
}

extension Color {
  /// A palette colour in SwiftUI; it still resolves in the view's appearance.
  init(_ color: NSColor) { self.init(nsColor: color) }
}

/// A size and weight of the system font, for SwiftUI text and for `SelectableText`.
struct TextStyle {
  let size: CGFloat
  var weight: NSFont.Weight = .regular
  /// Between lines, for text that wraps: about 1.5 times the size from baseline to baseline.
  var lineSpacing: CGFloat = 0
  var tracking: CGFloat = 0

  var font: Font { Font(nsFont as CTFont) }
  var nsFont: NSFont { .systemFont(ofSize: size, weight: weight) }

  /// One line of this style, as a text view lays it out (the line spacing only goes between
  /// lines); a placeholder this tall keeps the panel's height when the text replaces it.
  var lineHeight: CGFloat {
    NSLayoutManager().defaultLineHeight(for: nsFont).rounded(.up)
  }
}

/// The type scale of the panel and the app's windows (Design/option-a/README.md, 字体).
/// Measures only the word card uses are the card's own (`CardView`).
enum Typography {
  /// The word on a card.
  static let headword = TextStyle(size: 28, weight: .bold, tracking: -0.4)
  /// A translation, a translate-out.
  static let result = TextStyle(size: 17, weight: .medium, lineSpacing: 5)
  /// The text being proofread and its diff.
  static let proofread = TextStyle(size: 16, lineSpacing: 6)
  /// A notice's title, the meaning in this sentence.
  static let title = TextStyle(size: 15, weight: .semibold)
  /// Definitions, the input field.
  static let body = TextStyle(size: 15, lineSpacing: 4)
  /// The original above a result, what shows while waiting, the card's other meanings and
  /// examples.
  static let callout = TextStyle(size: 14, lineSpacing: 4)
  /// The context sentence, a back-translation, a notice's message.
  static let secondary = TextStyle(size: 13, lineSpacing: 3)
  /// The title of a capsule button.
  static let button = TextStyle(size: 13, weight: .semibold)
  /// A note under a result, a hint.
  static let note = TextStyle(size: 12.5, lineSpacing: 2)
  static let pill = TextStyle(size: 12.5, weight: .semibold)
  /// A section's small heading (本句, 例句, 搭配).
  static let label = TextStyle(size: 11.5, weight: .semibold)
  /// A small pill and a key cap.
  static let caption = TextStyle(size: 11, weight: .semibold)
}

enum Spacing {
  /// Around the panel's content: top and sides; the bottom, where the bar is, is less.
  static let panel: CGFloat = 22
  static let panelBottom: CGFloat = 16
  /// Between the blocks of the panel.
  static let section: CGFloat = 16
  /// Between the rows of a block.
  static let row: CGFloat = 10
  /// Between a pill and the text beside it, and an icon disc and its text.
  static let pill: CGFloat = 12
  /// Above the bottom bar, on top of `section`.
  static let barTop: CGFloat = 4
  static let iconButtons: CGFloat = 4
  /// Between a title and its message.
  static let tight: CGFloat = 4
  static let buttons: CGFloat = 8
  /// Inside a tinted block.
  static let blockVertical: CGFloat = 12
  static let blockHorizontal: CGFloat = 14
  /// Beside the input field's icon and text.
  static let input: CGFloat = 16
}

enum Radius {
  static let panel: CGFloat = 18
  static let block: CGFloat = 12
  static let iconButton: CGFloat = 8
  static let partOfSpeech: CGFloat = 6
  static let keycap: CGFloat = 5
}

enum Size {
  static let inputHeight: CGFloat = 48
  static let iconButton: CGFloat = 32
  /// The box of an icon, and the point size of an SF Symbol that fills it about as the
  /// mockups' stroked icons do.
  static let icon: CGFloat = 18
  static let symbol: CGFloat = 15
  /// The weight of every icon: light, near the mockups' thin strokes.
  static let symbolWeight = Font.Weight.light
  static let button: CGFloat = 32
  /// A button inside a note.
  static let compactButton: CGFloat = 26
  static let keycap: CGFloat = 18
  /// The tinted disc behind a notice's icon.
  static let disc: CGFloat = 36
  static let spinner: CGFloat = 14
  /// The fade of scrolling content above the bottom bar.
  static let scrollFade: CGFloat = 28
  /// The spinner's ring, as a share of the accent.
  static let spinnerTrack: CGFloat = 0.2
  /// A disabled icon button's icon, as a share of its colour.
  static let disabledOpacity: CGFloat = 0.35
  /// A key cap on the primary button: white at this opacity.
  static let keycapOnFill: CGFloat = 0.22
  /// A key cap on a secondary button: the text colour at this opacity, so it shows on the
  /// neutral tint in either appearance.
  static let keycapOnTint: CGFloat = 0.1
}
