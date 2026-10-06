// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

extension HotkeyRole {
  var title: String {
    switch self {
    case .read:
      String(
        localized: "Read", table: "Hotkeys",
        comment: "Name of the shortcut that looks up or translates the selection")
    case .write:
      String(
        localized: "Write", table: "Hotkeys",
        comment: "Name of the shortcut that corrects or translates what the user is writing")
    }
  }

  var summary: String {
    switch self {
    case .read:
      String(
        localized: "Look up or translate the selected text.", table: "Hotkeys",
        comment: "What the Read shortcut does")
    case .write:
      String(
        localized: "Correct, polish or translate what you are writing.", table: "Hotkeys",
        comment: "What the Write shortcut does")
    }
  }
}

extension HotkeyProblem {
  var message: String {
    switch self {
    case .needsModifier:
      String(
        localized: "Add ⌃, ⌥ or ⌘ so the key does not type text.", table: "Hotkeys",
        comment: "A shortcut was recorded without a modifier key")
    case .appShortcut:
      String(
        localized: "Shortcuts with only ⌘ clash with app menus. Add ⌃ or ⌥.", table: "Hotkeys",
        comment: "A shortcut used only Command (and maybe Shift)")
    case .reserved:
      String(
        localized: "macOS already uses this shortcut.", table: "Hotkeys",
        comment: "The shortcut is reserved by the system")
    case .usedBy(.read):
      String(
        localized: "The Read shortcut already uses this.", table: "Hotkeys",
        comment: "The other shortcut already has this combination")
    case .usedBy(.write):
      String(
        localized: "The Write shortcut already uses this.", table: "Hotkeys",
        comment: "The other shortcut already has this combination")
    case .registrationFailed(let status):
      // Another app holding the same combination does not make registration fail
      // (observed on macOS 26.5), so the message does not blame another app.
      String(
        localized: "macOS did not accept this shortcut (error \(status)). Try another one.",
        table: "Hotkeys",
        comment: "Registering the global shortcut failed. The argument is an error number")
    }
  }
}
