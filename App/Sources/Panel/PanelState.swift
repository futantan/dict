// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// Everything the result panel shows (architecture 11.1). The session coordinator builds
/// these values and hands them to `PanelController`; the panel never decides what to show.
struct PanelState: Sendable, Equatable {
  /// The captured or typed text, shown above the result; nil while it is still being read.
  var source: String?
  var phase: PanelPhase
  /// A remark under a generating, finished or partial result, for example that Apple
  /// Translation stood in for a failed model, or why a result is partial.
  var note: PanelNote?

  init(source: String? = nil, phase: PanelPhase, note: PanelNote? = nil) {
    self.source = source
    self.phase = phase
    self.note = note
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
  /// The complete result.
  case result(String)
  /// A result that stopped before it was complete: cut off at the length limit, or the
  /// stream failed after text showed. The note says why. It is shown and can be copied, but
  /// it must never be used for replacing (architecture 6.3).
  case partial(String)
  /// Something went wrong; the caller supplies the wording.
  case failure(PanelNotice)
  /// A permission or a model is missing; the content comes from the caller (architecture
  /// 11.1, M1.10).
  case needsSetup(PanelNotice)
  /// The Write key is proofreading this text.
  case checking(String)
  /// The proofread text as a diff of the original; Return replaces the selection with it
  /// when `canReplace`.
  case corrected(Correction)

  /// The text ⌘C copies when nothing in the panel is selected.
  var copyableText: String? {
    switch self {
    case .generating(let text), .result(let text), .partial(let text): text.isEmpty ? nil : text
    case .corrected(let correction): correction.text
    case .input, .reading, .failure, .needsSetup, .checking: nil
    }
  }

  /// Return replaces the selection.
  var canReplace: Bool {
    if case .corrected(let correction) = self { correction.canReplace } else { false }
  }
}

/// A finished proofread (architecture 6.7).
struct Correction: Sendable, Equatable {
  /// The original text with each change in place.
  var segments: [DiffSegment]
  /// The corrected text.
  var text: String
  var changeCount: Int
  /// There are changes and the selection's field can be written (architecture 4.3).
  var canReplace: Bool

  init(_ applied: AppliedEdits, replaceable: Bool) {
    segments = applied.segments
    text = applied.text
    changeCount = applied.changeCount
    canReplace = replaceable && applied.changeCount > 0
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

/// A line under the result, with an optional button at its end, for example "Open Settings"
/// when the model failed because of its key.
struct PanelNote: Sendable, Equatable {
  var text: String
  /// Reported through `PanelController.onAction` like a notice button; never the default.
  var action: PanelAction?

  init(_ text: String, action: PanelAction? = nil) {
    self.text = text
    self.action = action
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
