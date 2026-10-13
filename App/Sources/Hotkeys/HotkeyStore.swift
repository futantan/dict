// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Persists the two shortcuts in UserDefaults, one JSON value per role under
/// `hotkey.<role>`. A missing or unreadable value means the role has no shortcut.
/// Combinations keep the v0.1.0 format; see `Hotkey` for double presses.
struct HotkeyStore {
  let defaults: UserDefaults

  private static func key(_ role: HotkeyRole) -> String { "hotkey.\(role.rawValue)" }

  func load() -> [HotkeyRole: Hotkey] {
    var hotkeys: [HotkeyRole: Hotkey] = [:]
    for role in HotkeyRole.allCases {
      guard let data = defaults.data(forKey: Self.key(role)),
        let hotkey = try? JSONDecoder().decode(Hotkey.self, from: data)
      else { continue }
      hotkeys[role] = hotkey
    }
    return hotkeys
  }

  func save(_ hotkeys: [HotkeyRole: Hotkey]) {
    for role in HotkeyRole.allCases {
      if let hotkey = hotkeys[role], let data = try? JSONEncoder().encode(hotkey) {
        defaults.set(data, forKey: Self.key(role))
      } else {
        defaults.removeObject(forKey: Self.key(role))
      }
    }
  }

  func save(_ combos: [HotkeyRole: KeyCombo]) {
    save(combos.mapValues(Hotkey.combo))
  }
}
