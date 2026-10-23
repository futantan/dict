// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// Persists `Preferences` in UserDefaults as one JSON value under `preferences`.
/// A missing or unreadable value means the defaults.
struct PreferencesStore {
  static let key = "preferences"

  let defaults: UserDefaults

  func load() -> Preferences {
    guard let data = defaults.data(forKey: Self.key),
      let preferences = try? JSONDecoder().decode(Preferences.self, from: data)
    else { return Preferences() }
    return preferences
  }

  func save(_ preferences: Preferences) {
    guard let data = try? JSONEncoder().encode(preferences) else { return }
    defaults.set(data, forKey: Self.key)
  }
}
