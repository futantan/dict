// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@testable import DictApp

struct KeyComboTests {
  @Test func persistedFormIsStable() throws {
    let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_D), modifiers: [.control, .option])
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys

    let json = String(decoding: try encoder.encode(combo), as: UTF8.self)

    #expect(json == #"{"keyCode":2,"modifiers":["control","option"]}"#)
    #expect(try JSONDecoder().decode(KeyCombo.self, from: Data(json.utf8)) == combo)
  }

  @Test func unknownModifierNamesFailToDecode() {
    let json = #"{"keyCode":2,"modifiers":["hyper"]}"#
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(KeyCombo.self, from: Data(json.utf8))
    }
  }

  @Test func modifiersComeFromEventFlagsIgnoringTheRest() {
    let flags: NSEvent.ModifierFlags = [.command, .shift, .capsLock, .function, .numericPad]
    #expect(KeyCombo.Modifiers(flags) == [.command, .shift])
  }

  @Test func carbonModifiersMatchTheCarbonMasks() {
    let all: KeyCombo.Modifiers = [.command, .shift, .option, .control]
    #expect(all.carbon == UInt32(cmdKey | shiftKey | optionKey | controlKey))
    #expect(
      KeyCombo.Modifiers(carbon: UInt32(cmdKey | controlKey | 0x2_0000)) == [.command, .control])
  }
}
