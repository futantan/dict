// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Builds the menu shown from the menu bar icon.
@MainActor
enum StatusMenu {
  static func make(appName: String) -> NSMenu {
    let menu = NSMenu()

    // A nil target sends the action up the responder chain, which ends at the app delegate.
    menu.addItem(
      withTitle: String(
        localized: "About \(appName)", comment: "Menu item that opens the About panel"),
      action: #selector(AppDelegate.showAbout(_:)),
      keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: String(localized: "Quit \(appName)", comment: "Menu item that quits the app"),
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")

    return menu
  }
}
