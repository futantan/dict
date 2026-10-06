// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import Foundation

/// Why a combination cannot be used, or why a saved one is not working.
enum HotkeyProblem: Equatable, Sendable {
  /// A character key without ⌃, ⌥ or ⌘ would type text.
  case needsModifier
  /// ⌘ or ⌘⇧ alone collides with app menu shortcuts.
  case appShortcut
  /// macOS already uses it (System Settings > Keyboard > Keyboard Shortcuts, or built in).
  case reserved
  /// The other role already has it.
  case usedBy(HotkeyRole)
  /// `RegisterEventHotKey` returned a non-zero status.
  case registrationFailed(OSStatus)
}

/// Pure rules for choosing and showing combinations; the system queries live in
/// `KeyboardLayout` and `SystemShortcuts`.
enum HotkeyRules {
  /// Checks `combo` for `role`. ⌥ with a letter is allowed even though it types a
  /// character such as "å": the user chose it, as they would in Raycast or macOS itself.
  static func problem(
    for combo: KeyCombo,
    role: HotkeyRole,
    assigned: [HotkeyRole: KeyCombo],
    reserved: Set<KeyCombo>
  ) -> HotkeyProblem? {
    let modifiers = combo.modifiers
    let isFunctionKey = functionKeyNames[combo.keyCode] != nil
    if !isFunctionKey && modifiers.isDisjoint(with: [.control, .option, .command]) {
      return .needsModifier
    }
    if !isFunctionKey && modifiers.contains(.command)
      && modifiers.isDisjoint(with: [.control, .option])
    {
      return .appShortcut
    }
    if reserved.contains(combo) { return .reserved }
    if let other = assigned.first(where: { $0.key != role && $0.value == combo })?.key {
      return .usedBy(other)
    }
    return nil
  }

  /// Modifiers in menu order followed by the key name, for example "⌃⌥D".
  static func displayString(_ combo: KeyCombo, keyName: String) -> String {
    let symbols: [(KeyCombo.Modifiers, String)] = [
      (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]
    return symbols.filter { combo.modifiers.contains($0.0) }.map(\.1).joined() + keyName
  }

  /// The name printed on the key: a fixed symbol for non-character keys, otherwise what
  /// the key types in the current layout (`typed`), upper-cased.
  static func keyName(keyCode: UInt16, typed: String?) -> String {
    if let name = functionKeyNames[keyCode] ?? specialKeyNames[keyCode] { return name }
    if keyCode == UInt16(kVK_Space) {
      return String(localized: "Space", table: "Hotkeys", comment: "Name of the space bar key")
    }
    guard let typed, let scalar = typed.unicodeScalars.first,
      !CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains(scalar)
    else { return "#\(keyCode)" }
    return typed.uppercased()
  }

  private static let functionKeyNames: [UInt16: String] = {
    let codes = [
      kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
      kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]
    return Dictionary(
      uniqueKeysWithValues: codes.enumerated().map { (UInt16($0.element), "F\($0.offset + 1)") })
  }()

  private static let specialKeyNames: [UInt16: String] = [
    UInt16(kVK_Return): "↩", UInt16(kVK_ANSI_KeypadEnter): "⌤", UInt16(kVK_Tab): "⇥",
    UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "⎋",
    UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→", UInt16(kVK_UpArrow): "↑",
    UInt16(kVK_DownArrow): "↓", UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘",
    UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟",
  ]
}
