// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Persists the two combinations in UserDefaults, one JSON value per role under
/// `hotkey.<role>`. A missing or unreadable value means the role has no shortcut.
struct HotkeyStore {
  let defaults: UserDefaults

  private static func key(_ role: HotkeyRole) -> String { "hotkey.\(role.rawValue)" }

  func load() -> [HotkeyRole: KeyCombo] {
    var combos: [HotkeyRole: KeyCombo] = [:]
    for role in HotkeyRole.allCases {
      guard let data = defaults.data(forKey: Self.key(role)),
        let combo = try? JSONDecoder().decode(KeyCombo.self, from: data)
      else { continue }
      combos[role] = combo
    }
    return combos
  }

  func save(_ combos: [HotkeyRole: KeyCombo]) {
    for role in HotkeyRole.allCases {
      if let combo = combos[role], let data = try? JSONEncoder().encode(combo) {
        defaults.set(data, forKey: Self.key(role))
      } else {
        defaults.removeObject(forKey: Self.key(role))
      }
    }
  }
}
