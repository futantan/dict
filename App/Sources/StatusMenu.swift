// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Builds the menu shown from the menu bar icon, in the order of architecture 11.4.
@MainActor
enum StatusMenu {
  /// - Parameter warnings: problems with the shortcuts, shown first; each opens the
  ///   shortcut settings.
  static func make(appName: String, warnings: [String] = []) -> NSMenu {
    let menu = NSMenu()

    for warning in warnings {
      let item = menu.addItem(
        withTitle: warning, action: #selector(AppDelegate.showShortcutSettings(_:)),
        keyEquivalent: "")
      item.image = NSImage(
        systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
    }
    if !warnings.isEmpty { menu.addItem(.separator()) }

    // A nil target sends the action up the responder chain, which ends at the app delegate.
    menu.addItem(
      withTitle: String(
        localized: "Settings…", table: "Settings", comment: "Menu item that opens Settings"),
      action: #selector(AppDelegate.showSettings(_:)),
      keyEquivalent: ",")
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

extension HotkeyRole {
  /// A menu line for a shortcut that does not work as saved.
  func warning(_ problem: HotkeyProblem) -> String {
    String(
      localized: "\(title) shortcut: \(problem.message)",
      comment:
        "Menu item for a shortcut problem; the arguments are the shortcut name and the problem")
  }
}
