// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import Testing

@testable import DictApp

struct HotkeyRulesTests {
  private static let keyA = UInt16(kVK_ANSI_A)
  private static let key1 = UInt16(kVK_ANSI_1)
  private static let f18 = UInt16(kVK_F18)

  private func combo(_ keyCode: UInt16, _ modifiers: KeyCombo.Modifiers) -> KeyCombo {
    KeyCombo(keyCode: keyCode, modifiers: modifiers)
  }

  private func problem(
    _ combo: KeyCombo,
    role: HotkeyRole = .read,
    assigned: [HotkeyRole: KeyCombo] = [:],
    reserved: Set<KeyCombo> = []
  ) -> HotkeyProblem? {
    HotkeyRules.problem(
      for: .combo(combo), role: role, assigned: assigned.mapValues(Hotkey.combo), reserved: reserved
    )
  }

  @Test func plainOrShiftedCharacterKeysNeedAModifier() {
    #expect(problem(combo(Self.keyA, [])) == .needsModifier)
    #expect(problem(combo(Self.keyA, .shift)) == .needsModifier)
  }

  @Test func functionKeysMayStandAlone() {
    #expect(problem(combo(Self.f18, [])) == nil)
    #expect(problem(combo(Self.f18, .shift)) == nil)
  }

  @Test func commandWithoutControlOrOptionClashesWithAppMenus() {
    #expect(problem(combo(Self.keyA, .command)) == .appShortcut)
    #expect(problem(combo(Self.keyA, [.command, .shift])) == .appShortcut)
    #expect(problem(combo(Self.keyA, [.command, .option])) == nil)
    #expect(problem(combo(Self.keyA, [.command, .control])) == nil)
    #expect(problem(combo(Self.f18, .command)) == nil)
  }

  @Test func systemShortcutsAreRejected() {
    let spotlight = combo(UInt16(kVK_Space), [.control, .option])
    #expect(problem(spotlight, reserved: [spotlight]) == .reserved)
  }

  @Test func theOtherRolesComboIsRejectedButTheSameRolesIsNot() {
    let mine = combo(Self.keyA, [.control, .option])
    #expect(problem(mine, role: .read, assigned: [.write: mine]) == .usedBy(.write))
    #expect(problem(mine, role: .read, assigned: [.read: mine]) == nil)
  }

  /// ⌥ with a letter is allowed even though it types a character such as "å", as in
  /// Raycast and macOS itself.
  @Test func optionLettersAreAccepted() {
    #expect(problem(combo(Self.keyA, .option)) == nil)
    #expect(problem(combo(Self.keyA, [.option, .shift])) == nil)
    #expect(problem(combo(Self.key1, .option)) == nil)
  }

  @Test func displayStringOrdersModifiersLikeMacOSMenus() {
    let all = combo(Self.keyA, [.command, .shift, .option, .control])
    #expect(HotkeyRules.displayString(all, keyName: "A") == "⌃⌥⇧⌘A")
    #expect(HotkeyRules.displayString(combo(Self.f18, []), keyName: "F18") == "F18")
  }

  @Test func keyNamesUseSymbolsForSpecialKeysAndTheLayoutCharacterOtherwise() {
    #expect(HotkeyRules.keyName(keyCode: UInt16(kVK_F5), typed: nil) == "F5")
    #expect(HotkeyRules.keyName(keyCode: UInt16(kVK_LeftArrow), typed: nil) == "←")
    #expect(HotkeyRules.keyName(keyCode: UInt16(kVK_Return), typed: "\r") == "↩")
    #expect(HotkeyRules.keyName(keyCode: Self.keyA, typed: "q") == "Q")
    #expect(HotkeyRules.keyName(keyCode: UInt16(kVK_ANSI_Grave), typed: "`") == "`")
    #expect(HotkeyRules.keyName(keyCode: Self.keyA, typed: nil) == "#0")
  }

  @Test func aDoublePressNeedsNoOtherKeyAndIsNeverReserved() {
    for key in ModifierKey.allCases {
      #expect(
        HotkeyRules.problem(
          for: .doubleTap(key), role: .read, assigned: [:], reserved: [combo(Self.keyA, [])]) == nil
      )
    }
  }

  @Test func theOtherRolesDoublePressIsRejected() {
    let assigned: [HotkeyRole: Hotkey] = [.write: .doubleTap(.leftOption)]
    let problem = { (hotkey: Hotkey) in
      HotkeyRules.problem(for: hotkey, role: .read, assigned: assigned, reserved: [])
    }
    #expect(problem(.doubleTap(.leftOption)) == .usedBy(.write))
    #expect(problem(.doubleTap(.rightOption)) == nil)
    #expect(problem(.combo(combo(Self.keyA, .option))) == nil)
  }

  @Test func doublePressesOfCommandAndControlComeWithANotice() {
    #expect(HotkeyRules.notice(for: .doubleTap(.leftCommand)) == .systemDoublePress)
    #expect(HotkeyRules.notice(for: .doubleTap(.rightCommand)) == .systemDoublePress)
    #expect(HotkeyRules.notice(for: .doubleTap(.rightControl)) == .systemDoublePress)
    #expect(HotkeyRules.notice(for: .doubleTap(.leftOption)) == nil)
    #expect(HotkeyRules.notice(for: .doubleTap(.leftShift)) == nil)
    #expect(HotkeyRules.notice(for: .combo(combo(Self.keyA, [.control, .command]))) == nil)
  }

  @Test func aDoublePressShowsTheKeyTwice() {
    #expect(HotkeyRules.displayString(doubleTap: .leftOption) == "⌥ ⌥")
    #expect(HotkeyRules.displayString(doubleTap: .leftControl) == "⌃ ⌃")
    #expect(HotkeyRules.displayString(doubleTap: .leftShift) == "⇧ ⇧")
    #expect(HotkeyRules.displayString(doubleTap: .rightCommand).hasSuffix("⌘ ⌘"))
    #expect(HotkeyRules.displayString(doubleTap: .rightCommand) != "⌘ ⌘")
  }
}
