// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Testing

@testable import DictApp

struct PanelKeysTests {
  struct Case: Sendable, CustomTestStringConvertible {
    let name: String
    var keyCode: UInt16 = 0
    var characters: String?
    var modifiers: UInt = 0
    var marked = false
    var selected = false
    var result = false
    let expected: PanelKeyRoute

    var testDescription: String { name }
  }

  private static let command = NSEvent.ModifierFlags.command.rawValue
  private static let shift = NSEvent.ModifierFlags.shift.rawValue

  static let cases: [Case] = [
    Case(name: "Esc hides", keyCode: 53, characters: "\u{1b}", expected: .dismiss),
    Case(
      name: "Esc while composing goes to the input method", keyCode: 53, characters: "\u{1b}",
      marked: true, expected: .pass),
    Case(
      name: "Return while composing goes to the input method", keyCode: 36, characters: "\r",
      marked: true, expected: .pass),
    Case(
      name: "Tab while composing goes to the input method", keyCode: 48, characters: "\t",
      marked: true, expected: .pass),
    Case(name: "Return is left to the text field", keyCode: 36, characters: "\r", expected: .pass),
    Case(
      name: "⌘Esc is not Esc", keyCode: 53, characters: "\u{1b}", modifiers: command,
      expected: .pass),
    Case(
      name: "⌘C without a selection copies the result", keyCode: 8, characters: "c",
      modifiers: command, result: true, expected: .copyResult),
    Case(
      name: "⌘C with a selection copies the selection", keyCode: 8, characters: "c",
      modifiers: command, selected: true, result: true,
      expected: .edit(#selector(NSText.copy(_:)))),
    Case(
      name: "⌘C without a result goes to the text field", keyCode: 8, characters: "c",
      modifiers: command, expected: .edit(#selector(NSText.copy(_:)))),
    Case(
      name: "⌘C with Caps Lock", keyCode: 8, characters: "C",
      modifiers: command | NSEvent.ModifierFlags.capsLock.rawValue, result: true,
      expected: .copyResult),
    Case(
      name: "⌘V pastes", keyCode: 9, characters: "v", modifiers: command,
      expected: .edit(#selector(NSText.paste(_:)))),
    Case(
      name: "⌘X cuts", keyCode: 7, characters: "x", modifiers: command,
      expected: .edit(#selector(NSText.cut(_:)))),
    Case(
      name: "⌘A selects all", keyCode: 0, characters: "a", modifiers: command,
      expected: .edit(#selector(NSText.selectAll(_:)))),
    Case(
      name: "⌘Z undoes", keyCode: 6, characters: "z", modifiers: command,
      expected: .edit(Selector(("undo:")))),
    Case(
      name: "⇧⌘Z redoes", keyCode: 6, characters: "z", modifiers: command | shift,
      expected: .edit(Selector(("redo:")))),
    Case(
      name: "⌥⌘C is not copy", keyCode: 8, characters: "c",
      modifiers: command | NSEvent.ModifierFlags.option.rawValue, result: true, expected: .pass),
    Case(
      name: "⌘V while composing goes to the input method", keyCode: 9, characters: "v",
      modifiers: command, marked: true, expected: .pass),
    Case(name: "plain letters are typed", keyCode: 0, characters: "a", expected: .pass),
  ]

  @Test(arguments: cases)
  func route(_ c: Case) {
    let route = PanelKeys.route(
      keyCode: c.keyCode, characters: c.characters,
      modifiers: NSEvent.ModifierFlags(rawValue: c.modifiers), hasMarkedText: c.marked,
      hasSelectedText: c.selected, hasResult: c.result)
    #expect(route == c.expected)
  }
}
