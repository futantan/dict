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

/// A shortcut that works but may also trigger something in macOS. Shown, not refused.
enum HotkeyNotice: Equatable, Sendable {
  /// Siri and Dictation can be set to a double press of ⌘ or ⌃.
  case systemDoublePress
}

/// Pure rules for choosing and showing shortcuts; the system queries live in
/// `KeyboardLayout` and `SystemShortcuts`.
enum HotkeyRules {
  /// Checks `hotkey` for `role`. ⌥ with a letter is allowed even though it types a
  /// character such as "å": the user chose it, as they would in Raycast or macOS itself.
  /// A double press only has to differ from the other role's: two double presses of the
  /// same modifier clash even if one is right-hand only, since either side covers it.
  static func problem(
    for hotkey: Hotkey,
    role: HotkeyRole,
    assigned: [HotkeyRole: Hotkey],
    reserved: Set<KeyCombo>
  ) -> HotkeyProblem? {
    if case .combo(let combo) = hotkey, let problem = comboProblem(combo, reserved: reserved) {
      return problem
    }
    if let other = assigned.first(where: { $0.key != role && clash($0.value, hotkey) })?.key {
      return .usedBy(other)
    }
    return nil
  }

  static func notice(for hotkey: Hotkey) -> HotkeyNotice? {
    guard case .doubleTap(let doubleTap) = hotkey,
      [.command, .control].contains(doubleTap.modifier)
    else { return nil }
    return .systemDoublePress
  }

  private static func clash(_ a: Hotkey, _ b: Hotkey) -> Bool {
    if case .doubleTap(let x) = a, case .doubleTap(let y) = b { return x.modifier == y.modifier }
    return a == b
  }

  private static func comboProblem(_ combo: KeyCombo, reserved: Set<KeyCombo>) -> HotkeyProblem? {
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
    return nil
  }

  /// Modifiers in menu order followed by the key name, for example "⌃⌥D".
  static func displayString(_ combo: KeyCombo, keyName: String) -> String {
    symbols(combo.modifiers) + keyName
  }

  /// The key twice, for example "⌥ ⌥" for either side; right-hand only is marked as such.
  static func displayString(_ doubleTap: DoubleTap) -> String {
    let symbol = symbols(doubleTap.modifier)
    let pair = "\(symbol) \(symbol)"
    guard doubleTap.isRightOnly else { return pair }
    return String(
      localized: "Right \(pair)", table: "Hotkeys",
      comment: "A shortcut that is the right-hand modifier key pressed twice, for example ⌘ ⌘")
  }

  private static func symbols(_ modifiers: KeyCombo.Modifiers) -> String {
    let symbols: [(KeyCombo.Modifiers, String)] = [
      (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]
    return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined()
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
