// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox

/// The two global shortcuts (architecture 10.1). Neither has a default.
enum HotkeyRole: String, CaseIterable, Sendable {
  case read
  case write
}

/// A key plus modifiers, identified by the hardware key code so it survives layout changes.
/// Persisted as `{"keyCode": 2, "modifiers": ["control", "option"]}`.
struct KeyCombo: Hashable, Sendable, Codable {
  let keyCode: UInt16
  let modifiers: Modifiers

  struct Modifiers: OptionSet, Hashable, Sendable {
    let rawValue: UInt8

    static let control = Modifiers(rawValue: 1 << 0)
    static let option = Modifiers(rawValue: 1 << 1)
    static let shift = Modifiers(rawValue: 1 << 2)
    static let command = Modifiers(rawValue: 1 << 3)

    /// In menu order (⌃⌥⇧⌘), with their persisted names, Carbon masks and event flags.
    static let all:
      [(modifier: Modifiers, name: String, carbon: Int, flag: NSEvent.ModifierFlags)] = [
        (.control, "control", controlKey, .control),
        (.option, "option", optionKey, .option),
        (.shift, "shift", shiftKey, .shift),
        (.command, "command", cmdKey, .command),
      ]

    init(rawValue: UInt8) { self.rawValue = rawValue }

    init(_ flags: NSEvent.ModifierFlags) {
      self = Modifiers(Self.all.filter { flags.contains($0.flag) }.map(\.modifier))
    }

    /// Ignores bits other than the four modifiers, such as the fn bit on arrow keys.
    init(carbon: UInt32) {
      self = Modifiers(Self.all.filter { carbon & UInt32($0.carbon) != 0 }.map(\.modifier))
    }

    var carbon: UInt32 {
      Self.all.filter { contains($0.modifier) }.reduce(0) { $0 | UInt32($1.carbon) }
    }
  }
}

extension KeyCombo.Modifiers: Codable {
  init(from decoder: any Decoder) throws {
    let names = try decoder.singleValueContainer().decode([String].self)
    self = []
    for name in names {
      guard let entry = Self.all.first(where: { $0.name == name }) else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "Unknown modifier \(name)"))
      }
      insert(entry.modifier)
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(Self.all.filter { contains($0.modifier) }.map(\.name))
  }
}
