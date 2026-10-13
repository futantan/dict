// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox

/// What triggers a role: a key with modifiers, registered with Carbon, or a modifier key
/// pressed twice, seen by an event monitor (architecture 10.1).
///
/// A combination is persisted exactly as `KeyCombo` always was, so v0.1.0 reads it.
/// A double press is persisted as `{"doubleTap": "rightCommand"}`; v0.1.0 cannot decode
/// that and treats the role as having no shortcut.
enum Hotkey: Hashable, Sendable {
  case combo(KeyCombo)
  case doubleTap(ModifierKey)
}

extension Hotkey: Codable {
  private enum CodingKeys: String, CodingKey {
    case doubleTap
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if container.contains(.doubleTap) {
      self = .doubleTap(try container.decode(ModifierKey.self, forKey: .doubleTap))
    } else {
      self = .combo(try KeyCombo(from: decoder))
    }
  }

  func encode(to encoder: any Encoder) throws {
    switch self {
    case .combo(let combo):
      try combo.encode(to: encoder)
    case .doubleTap(let key):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(key, forKey: .doubleTap)
    }
  }
}

/// One physical modifier key. Left and right are different keys, as in Raycast.
enum ModifierKey: String, CaseIterable, Sendable, Codable {
  case leftControl
  case rightControl
  case leftOption
  case rightOption
  case leftShift
  case rightShift
  case leftCommand
  case rightCommand

  var keyCode: UInt16 {
    switch self {
    case .leftControl: UInt16(kVK_Control)
    case .rightControl: UInt16(kVK_RightControl)
    case .leftOption: UInt16(kVK_Option)
    case .rightOption: UInt16(kVK_RightOption)
    case .leftShift: UInt16(kVK_Shift)
    case .rightShift: UInt16(kVK_RightShift)
    case .leftCommand: UInt16(kVK_Command)
    case .rightCommand: UInt16(kVK_RightCommand)
    }
  }

  var modifier: KeyCombo.Modifiers {
    switch self {
    case .leftControl, .rightControl: .control
    case .leftOption, .rightOption: .option
    case .leftShift, .rightShift: .shift
    case .leftCommand, .rightCommand: .command
    }
  }

  var isRight: Bool {
    switch self {
    case .rightControl, .rightOption, .rightShift, .rightCommand: true
    default: false
    }
  }

  init?(keyCode: UInt16) {
    guard let key = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
    self = key
  }

  /// The device-dependent bit for this key in `NSEvent.ModifierFlags.rawValue`
  /// (`NX_DEVICE…KEYMASK` in IOKit's IOLLEvent.h).
  private var deviceMask: UInt {
    switch self {
    case .leftControl: 0x0001
    case .leftShift: 0x0002
    case .rightShift: 0x0004
    case .leftCommand: 0x0008
    case .rightCommand: 0x0010
    case .leftOption: 0x0020
    case .rightOption: 0x0040
    case .rightControl: 0x2000
    }
  }

  /// The modifier keys held according to `flags`. Events that carry no left/right bits
  /// for a held modifier (some synthesized ones) count the key that changed, `changed`,
  /// when it is that modifier, otherwise the left key.
  static func held(in flags: NSEvent.ModifierFlags, changed: UInt16) -> Set<ModifierKey> {
    var held: Set<ModifierKey> = []
    for entry in KeyCombo.Modifiers.all where flags.contains(entry.flag) {
      let sides = allCases.filter { $0.modifier == entry.modifier }
      let bySide = sides.filter { flags.rawValue & $0.deviceMask != 0 }
      if !bySide.isEmpty {
        held.formUnion(bySide)
      } else if let key = ModifierKey(keyCode: changed), key.modifier == entry.modifier {
        held.insert(key)
      } else if let left = sides.first(where: { !$0.isRight }) {
        held.insert(left)
      }
    }
    return held
  }
}
