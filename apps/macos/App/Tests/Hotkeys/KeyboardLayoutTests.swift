// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import Testing

@testable import DictApp

/// Runs UCKeyTranslate against layouts that ship with macOS, whether or not they are enabled.
@MainActor
struct KeyboardLayoutTests {
  private func layout(_ id: String) throws -> KeyboardLayout {
    try #require(KeyboardLayout.installed(id: id))
  }

  private let keyA = UInt16(kVK_ANSI_A)

  @Test func theAKeyIsPrintedQOnFrenchAZERTY() throws {
    #expect(try layout("com.apple.keylayout.French").character(keyCode: keyA) == "q")
    #expect(try layout("com.apple.keylayout.US").character(keyCode: keyA) == "a")
  }

  @Test func deadKeysStillHaveAPrintableName() throws {
    let extended = try layout("com.apple.keylayout.USExtended")
    #expect(extended.character(keyCode: UInt16(kVK_ANSI_Grave)) == "`")
  }
}
