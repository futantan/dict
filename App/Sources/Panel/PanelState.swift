// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Everything the result panel shows (architecture 11.1). The session coordinator builds
/// these values and hands them to `PanelController`; the panel never decides what to show.
struct PanelState: Sendable, Equatable {
  /// The captured or typed text, shown above the result; nil while it is still being read.
  var source: String?
  var phase: PanelPhase

  init(source: String? = nil, phase: PanelPhase) {
    self.source = source
    self.phase = phase
  }

  /// The empty panel with a text field (architecture 10.4).
  static let input = PanelState(phase: .input)
}

enum PanelPhase: Sendable, Equatable {
  /// Waiting for typed text; Return submits it.
  case input
  /// The selection is still being read, for example through the clipboard fallback.
  case reading
  /// The result is streaming in; the value is the whole text so far and may be empty.
  case generating(String)
  /// The finished result.
  case result(String)
  /// Something went wrong; the caller supplies the wording.
  case failure(PanelNotice)
  /// A permission, model or language pack is missing; the content comes from the caller
  /// (architecture 11.1, M1.10).
  case needsSetup(PanelNotice)

  /// The text ⌘C copies when nothing in the panel is selected.
  var copyableText: String? {
    switch self {
    case .generating(let text), .result(let text): text.isEmpty ? nil : text
    case .input, .reading, .failure, .needsSetup: nil
    }
  }
}

/// A message with optional buttons, for the failure and needs-setup phases.
struct PanelNotice: Sendable, Equatable {
  /// An SF Symbol name; each phase has a default.
  var symbol: String?
  var title: String
  var message: String?
  /// Shown as buttons, trailing aligned; the panel reports a click through
  /// `PanelController.onAction` with the action's `id`.
  var actions: [PanelAction]

  init(symbol: String? = nil, title: String, message: String? = nil, actions: [PanelAction] = []) {
    self.symbol = symbol
    self.title = title
    self.message = message
    self.actions = actions
  }
}

struct PanelAction: Sendable, Equatable, Identifiable {
  /// Chosen by the caller, for example `"openAccessibilitySettings"`.
  let id: String
  let title: String
  /// The default action is prominent and answers Return.
  var isDefault: Bool

  init(id: String, title: String, isDefault: Bool = false) {
    self.id = id
    self.title = title
    self.isDefault = isDefault
  }
}

/// Why the panel hid itself. Hiding ends the session (architecture 11.1).
enum PanelDismissal: Sendable, Equatable {
  case escape
  case clickOutside
  /// Another app became active, for example through ⌘Tab.
  case appSwitched
}
