// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// What the panel does with a key press before the normal responder chain sees it
/// (architecture 11.1, 11.5).
enum PanelKeyRoute: Equatable {
  /// Hide the panel.
  case dismiss
  /// Copy the panel's result.
  case copyResult
  /// Send an editing action to the first responder. The app has no Edit menu, so nothing
  /// else turns ⌘C, ⌘V and the like into actions.
  case edit(Selector)
  /// Let the window handle the event as usual, which includes the input method.
  case pass
}

enum PanelKeys {
  static let escape: UInt16 = 53

  /// - Parameters:
  ///   - hasMarkedText: The focused text field holds uncommitted input-method text. Return,
  ///     Esc and Tab then belong to the input method.
  ///   - hasSelectedText: The focused text view has a non-empty selection.
  static func route(
    keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags,
    hasMarkedText: Bool, hasSelectedText: Bool, hasResult: Bool
  ) -> PanelKeyRoute {
    if hasMarkedText { return .pass }
    let modifiers = modifiers.intersection([.command, .shift, .option, .control])
    if keyCode == escape && modifiers.isEmpty { return .dismiss }
    guard modifiers == .command || modifiers == [.command, .shift] else { return .pass }

    switch (characters?.lowercased(), modifiers) {
    case ("c", .command):
      return hasSelectedText || !hasResult ? .edit(#selector(NSText.copy(_:))) : .copyResult
    case ("x", .command): return .edit(#selector(NSText.cut(_:)))
    case ("v", .command): return .edit(#selector(NSText.paste(_:)))
    case ("a", .command): return .edit(#selector(NSText.selectAll(_:)))
    case ("z", .command): return .edit(Selector(("undo:")))
    case ("z", [.command, .shift]): return .edit(Selector(("redo:")))
    default: return .pass
    }
  }
}
