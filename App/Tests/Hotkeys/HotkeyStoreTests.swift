// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import Foundation
import Testing

@testable import DictApp

/// The persisted form must stay readable both ways with v0.1.0, which stored a bare
/// `KeyCombo` per role.
final class HotkeyStoreTests {
  private let suiteName = "HotkeyStoreTests.\(UUID().uuidString)"
  private let defaults: UserDefaults
  private let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_D), modifiers: [.control, .option])

  init() throws {
    defaults = try #require(UserDefaults(suiteName: suiteName))
  }

  deinit {
    UserDefaults.standard.removePersistentDomain(forName: suiteName)
  }

  @Test func whatV010WroteLoadsAsACombination() {
    // Written by v0.1.0's `HotkeyStore`.
    defaults.set(
      Data(#"{"keyCode":2,"modifiers":["control","option"]}"#.utf8), forKey: "hotkey.read")

    #expect(HotkeyStore(defaults: defaults).load() == [.read: .combo(combo)])
  }

  @Test func aCombinationIsWrittenAsV010WroteIt() throws {
    HotkeyStore(defaults: defaults).save([.read: Hotkey.combo(combo)])

    let data = try #require(defaults.data(forKey: "hotkey.read"))
    // v0.1.0 decodes it with its own `KeyCombo`, which this one still is.
    #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == combo)
  }

  @Test func aDoublePressRoundTrips() throws {
    let store = HotkeyStore(defaults: defaults)
    store.save([.read: .doubleTap(.leftOption), .write: .doubleTap(.rightCommand)])

    #expect(store.load() == [.read: .doubleTap(.leftOption), .write: .doubleTap(.rightCommand)])
    let data = try #require(defaults.data(forKey: "hotkey.write"))
    #expect(String(decoding: data, as: UTF8.self) == #"{"doubleTap":"rightCommand"}"#)
  }

  /// v0.1.0 decodes with `try?` into `KeyCombo`: a double press fails, so that version
  /// shows the role as having no shortcut, without crashing.
  @Test func v010CannotReadADoublePress() throws {
    HotkeyStore(defaults: defaults).save([.read: Hotkey.doubleTap(.leftOption)])

    let data = try #require(defaults.data(forKey: "hotkey.read"))
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(KeyCombo.self, from: data) }
  }

  @Test func anUnknownModifierKeyMeansNoShortcut() {
    defaults.set(Data(#"{"doubleTap":"fn"}"#.utf8), forKey: "hotkey.read")
    defaults.set(Data(#"{"keyCode":2,"modifiers":["control"]}"#.utf8), forKey: "hotkey.write")

    #expect(
      HotkeyStore(defaults: defaults).load() == [
        .write: .combo(KeyCombo(keyCode: 2, modifiers: [.control]))
      ])
  }
}
