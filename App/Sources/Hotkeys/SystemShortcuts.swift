// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox

/// Combinations macOS keeps for itself.
@MainActor
enum SystemShortcuts {
  /// The enabled shortcuts from System Settings > Keyboard > Keyboard Shortcuts, plus a few
  /// built-in ones that are not listed there.
  static func reserved() -> Set<KeyCombo> {
    var unmanaged: Unmanaged<CFArray>?
    var combos = builtIn
    guard CopySymbolicHotKeys(&unmanaged) == noErr,
      let entries = unmanaged?.takeRetainedValue() as? [[String: Any]]
    else { return combos }
    for entry in entries where entry[kHISymbolicHotKeyEnabled as String] as? Bool == true {
      guard let code = entry[kHISymbolicHotKeyCode as String] as? Int,
        let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int,
        let keyCode = UInt16(exactly: code), keyCode != UInt16.max
      else { continue }
      combos.insert(
        KeyCombo(keyCode: keyCode, modifiers: .init(carbon: UInt32(truncatingIfNeeded: modifiers))))
    }
    return combos
  }

  /// Force Quit, Lock Screen, the emoji viewer and full screen.
  private static let builtIn: Set<KeyCombo> = [
    KeyCombo(keyCode: UInt16(kVK_Escape), modifiers: [.command, .option]),
    KeyCombo(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.control, .command]),
    KeyCombo(keyCode: UInt16(kVK_Space), modifiers: [.control, .command]),
    KeyCombo(keyCode: UInt16(kVK_ANSI_F), modifiers: [.control, .command]),
  ]
}
