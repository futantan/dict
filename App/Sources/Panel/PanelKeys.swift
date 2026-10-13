// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// What the panel does with a key press before the normal responder chain sees it
/// (architecture 11.1, 11.5).
enum PanelKeyRoute: Equatable {
  /// Hide the panel.
  case dismiss
  /// Copy the panel's result.
  case copyResult
  /// Replace the selection with the correction shown (architecture 11.5).
  case confirm
  /// Perform a panel action, as its button would: ⌘S and ⌘P on a word card.
  case perform(PanelAction.ID)
  /// Make the previous (-1) or next (+1) change of a correction current (architecture 11.5).
  case moveChange(Int)
  /// Accept the current change of a correction if it is declined, decline it if accepted.
  case toggleChange
  /// Send an editing action to the first responder. The app has no Edit menu, so nothing
  /// else turns ⌘C, ⌘V and the like into actions.
  case edit(Selector)
  /// Let the window handle the event as usual, which includes the input method.
  case pass
}

enum PanelKeys {
  static let escape: UInt16 = 53
  static let returnKey: UInt16 = 36
  static let keypadEnter: UInt16 = 76
  static let tab: UInt16 = 48
  static let space: UInt16 = 49
  static let leftArrow: UInt16 = 123
  static let rightArrow: UInt16 = 124

  /// - Parameters:
  ///   - hasMarkedText: The focused text field holds uncommitted input-method text. Return,
  ///     Esc and Tab then belong to the input method.
  ///   - hasSelectedText: The focused text view has a non-empty selection.
  ///   - canReplace: The panel shows a correction that Return writes into the app.
  ///   - showsCard: The panel shows a word card, which takes ⌘S and ⌘P.
  ///   - reviewsChanges: The panel shows a correction with changes and no control has
  ///     focus, so ← and → move between the changes and Space accepts or declines one. With
  ///     a button focused through Tab, Space presses the button as usual.
  static func route(
    keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags,
    hasMarkedText: Bool, hasSelectedText: Bool, hasResult: Bool, canReplace: Bool = false,
    showsCard: Bool = false, reviewsChanges: Bool = false
  ) -> PanelKeyRoute {
    if hasMarkedText { return .pass }
    let modifiers = modifiers.intersection([.command, .shift, .option, .control])
    if keyCode == escape && modifiers.isEmpty { return .dismiss }
    if canReplace && modifiers.isEmpty && (keyCode == returnKey || keyCode == keypadEnter) {
      return .confirm
    }
    if reviewsChanges && modifiers.isEmpty {
      switch keyCode {
      case leftArrow: return .moveChange(-1)
      case rightArrow: return .moveChange(1)
      case space: return .toggleChange
      default: break
      }
    }
    guard modifiers == .command || modifiers == [.command, .shift] else { return .pass }

    switch (characters?.lowercased(), modifiers) {
    case ("c", .command):
      return hasSelectedText || !hasResult ? .edit(#selector(NSText.copy(_:))) : .copyResult
    case ("x", .command): return .edit(#selector(NSText.cut(_:)))
    case ("v", .command): return .edit(#selector(NSText.paste(_:)))
    case ("a", .command): return .edit(#selector(NSText.selectAll(_:)))
    case ("z", .command): return .edit(Selector(("undo:")))
    case ("z", [.command, .shift]): return .edit(Selector(("redo:")))
    case ("s", .command) where showsCard: return .perform(CardStrings.learnAction)
    case ("p", .command) where showsCard: return .perform(CardStrings.pronounceAction)
    default: return .pass
    }
  }
}
