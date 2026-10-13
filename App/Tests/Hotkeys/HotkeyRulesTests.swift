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
          for: .doubleTap(DoubleTap(key)), role: .read, assigned: [:],
          reserved: [combo(Self.keyA, [])]) == nil
      )
    }
  }

  @Test func theOtherRolesDoublePressIsRejected() {
    let assigned: [HotkeyRole: Hotkey] = [.write: .doubleTap(DoubleTap(.leftOption))]
    let problem = { (hotkey: Hotkey) in
      HotkeyRules.problem(for: hotkey, role: .read, assigned: assigned, reserved: [])
    }
    #expect(problem(.doubleTap(DoubleTap(.leftOption))) == .usedBy(.write))
    // Either-side ⌥ ⌥ covers the right-hand key too.
    #expect(problem(.doubleTap(DoubleTap(.rightOption))) == .usedBy(.write))
    #expect(problem(.doubleTap(DoubleTap(.leftCommand))) == nil)
    #expect(problem(.combo(combo(Self.keyA, .option))) == nil)
  }

  @Test func twoRightHandDoublePressesOfDifferentModifiersCoexist() {
    let assigned: [HotkeyRole: Hotkey] = [.write: .doubleTap(DoubleTap(.rightCommand))]
    #expect(
      HotkeyRules.problem(
        for: .doubleTap(DoubleTap(.rightOption)), role: .read, assigned: assigned, reserved: [])
        == nil)
    #expect(
      HotkeyRules.problem(
        for: .doubleTap(DoubleTap(.leftCommand)), role: .read, assigned: assigned, reserved: [])
        == .usedBy(.write))
  }

  @Test func doublePressesOfCommandAndControlComeWithANotice() {
    #expect(HotkeyRules.notice(for: .doubleTap(DoubleTap(.leftCommand))) == .systemDoublePress)
    #expect(HotkeyRules.notice(for: .doubleTap(DoubleTap(.rightCommand))) == .systemDoublePress)
    #expect(HotkeyRules.notice(for: .doubleTap(DoubleTap(.rightControl))) == .systemDoublePress)
    #expect(HotkeyRules.notice(for: .doubleTap(DoubleTap(.leftOption))) == nil)
    #expect(HotkeyRules.notice(for: .doubleTap(DoubleTap(.leftShift))) == nil)
    #expect(HotkeyRules.notice(for: .combo(combo(Self.keyA, [.control, .command]))) == nil)
  }

  @Test func aDoublePressShowsTheKeyTwiceAndMarksRightHandOnly() {
    #expect(HotkeyRules.displayString(DoubleTap(.leftOption)) == "⌥ ⌥")
    #expect(HotkeyRules.displayString(DoubleTap(.leftControl)) == "⌃ ⌃")
    #expect(HotkeyRules.displayString(DoubleTap(.leftShift)) == "⇧ ⇧")
    // "Right ⌘ ⌘" or "右 ⌘ ⌘" depending on the host's language (HotkeyStringsTests).
    let right = HotkeyRules.displayString(DoubleTap(.rightCommand))
    #expect(right.hasSuffix(" ⌘ ⌘"))
    #expect(["Right ⌘ ⌘", "右 ⌘ ⌘"].contains(right))
  }

  @Test func aLeftHandRecordingMeansEitherSide() {
    let either = DoubleTap(.leftOption)
    #expect(!either.isRightOnly)
    #expect(either.matches(.leftOption))
    #expect(either.matches(.rightOption))
    #expect(!either.matches(.leftCommand))
  }

  @Test func aRightHandRecordingMeansOnlyThatKey() {
    let right = DoubleTap(.rightCommand)
    #expect(right.isRightOnly)
    #expect(right.matches(.rightCommand))
    #expect(!right.matches(.leftCommand))
    #expect(!right.matches(.rightOption))
  }
}
