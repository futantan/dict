// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// The main window's tokens beyond the panel's (Design/main-app/*.html). The light values
/// are the mockups'; the dark ones keep the same steps between layers as the panel's dark
/// palette (Design/option-a/README.md). The window's page itself is `Palette.panelFill`.
extension Palette {
  /// The sidebar, a step below the page.
  static let sidebarFill = windowColor(light: 0xF2F2F5, dark: 0x18181B)
  /// A card and the search field, a step above the page.
  static let cardFill = windowColor(light: 0xFFFFFF, dark: 0x2A2A2F)
  /// Between the rows of a card; the card's own edge is `separator`.
  static let rowSeparator = windowColor(light: 0xEDEDF0, dark: 0x38383E)
  /// A sidebar item and a row's quieter title.
  static let textQuiet = windowColor(light: 0x3A3A3C, dark: 0xD1D1D6)
  /// A destructive button: 「清除所有记录…」.
  static let dangerTint = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(srgbRed: 1, green: 0x6B / 255, blue: 0x60 / 255, alpha: 0.16)
      : NSColor(srgbRed: 0xFD / 255, green: 0xEC / 255, blue: 0xEB / 255, alpha: 1)
  }
  static let dangerOnTint = windowColor(light: 0xB3261E, dark: 0xFF8A80)

  private static func windowColor(light: UInt32, dark: UInt32) -> NSColor {
    NSColor(name: nil) { appearance in
      let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
      return NSColor(
        srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
  }
}

/// The window's type scale; the sizes the panel shares are taken from `Typography`.
enum WindowType {
  /// 「今天」, 「设置」.
  static let pageTitle = Typography.headword
  /// The date above the title.
  static let pageSubtitle = TextStyle(size: 13)
  /// After the title: 「48 个词」.
  static let pageTitleNote = TextStyle(size: 15, weight: .medium)
  /// 「最近查询」, a settings section.
  static let heading = Typography.title
  static let sidebarItem = TextStyle(size: 14)
  static let sidebarItemSelected = TextStyle(size: 14, weight: .semibold)
  /// A row of a card.
  static let row = TextStyle(size: 14)
  /// A word in a list.
  static let term = Typography.title
  /// The search field.
  static let search = TextStyle(size: 16)
  static let statValue = TextStyle(size: 28, weight: .bold)
  static let statUnit = TextStyle(size: 14, weight: .medium)
  static let statLabel = TextStyle(size: 12.5)
  static let statLabelEmphasis = TextStyle(size: 12.5, weight: .semibold)
  /// The app and time of a row, a count in the sidebar.
  static let detail = TextStyle(size: 12)
  static let badge = TextStyle(size: 12, weight: .semibold)
  /// A row's explanation under its title, a footnote under a card.
  static let footnote = Typography.note
}

enum WindowLayout {
  static let sidebarWidth: CGFloat = 232
  /// Around the sidebar's items: top below the traffic lights, sides, bottom.
  static let sidebarTop: CGFloat = 52
  static let sidebarSide: CGFloat = 12
  static let sidebarBottom: CGFloat = 16
  static let sidebarItemHeight: CGFloat = 34
  static let sidebarItemPadding: CGFloat = 10
  static let sidebarItemSpacing: CGFloat = 4
  /// Around a page: top, sides and bottom.
  static let pageTop: CGFloat = 40
  static let pageSide: CGFloat = 48
  static let pageBottom: CGFloat = 48
  /// Between the blocks of a page.
  static let pageSpacing: CGFloat = 28
  /// Above a page's scrolling content, so the top card's shadow is not clipped.
  static let shadowRoom: CGFloat = 4
  /// Between the title and the subtitle of a page.
  static let titleSpacing: CGFloat = 6
  /// Between the title and the note after it.
  static let titleNoteSpacing: CGFloat = 8
  /// Between a heading and its card.
  static let headingSpacing: CGFloat = 10
  static let cardRadius: CGFloat = 14
  static let cardRowVertical: CGFloat = 12
  static let cardRowHorizontal: CGFloat = 16
  static let rowMinHeight: CGFloat = 48
  /// The columns of a list row: the word and its tag (Design/main-app/home.html).
  static let termWidth: CGFloat = 120
  static let tagWidth: CGFloat = 44
  static let tagVertical: CGFloat = 2
  /// Around a list of short rows inside a card, and around each row.
  static let listInset: CGFloat = 8
  /// The narrower column beside a list: 「反复遇到，还没标要学」.
  static let sideColumnMinWidth: CGFloat = 280
  static let sideColumnMaxWidth: CGFloat = 340
  /// A small capsule button in a card.
  static let cardButtonHeight: CGFloat = 28
  static let cardButtonPadding: CGFloat = 12
  static let tileSpacing: CGFloat = 16
  static let tileVertical: CGFloat = 18
  static let tileHorizontal: CGFloat = 20
  static let searchHeight: CGFloat = 52
  /// The shortcut card at the bottom of the sidebar.
  static let shortcutCardRadius: CGFloat = 10
  static let shortcutCardPadding: CGFloat = 10
  /// The settings page's list of sections.
  static let settingsListWidth: CGFloat = 180
  static let settingsItemHeight: CGFloat = 32
  static let settingsColumnMaxWidth: CGFloat = 720
  static let settingsSpacing: CGFloat = 32
  /// The window's size when it first opens, and the smallest it gets.
  static let defaultSize = CGSize(width: 1280, height: 800)
  static let minimumSize = CGSize(width: 960, height: 620)
}
