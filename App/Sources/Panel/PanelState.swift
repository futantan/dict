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
  /// A translation of a word or phrase offers 「查这个词」, for text `classify` sent to the
  /// wrong place (architecture 5.1).
  var offersLookUp: Bool

  init(
    source: String? = nil, phase: PanelPhase, note: PanelNote? = nil, offersLookUp: Bool = false
  ) {
    self.source = source
    self.phase = phase
    self.note = note
    self.offersLookUp = offersLookUp
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
  /// The word card of a looked-up word or phrase: the dictionary layer, then the model's
  /// card as it streams in (architecture 6.6).
  case card(CardState)

  /// The text ⌘C copies when nothing in the panel is selected.
  var copyableText: String? {
    switch self {
    case .generating(let text), .result(let text), .partial(let text): text.isEmpty ? nil : text
    case .corrected(let correction): correction.text
    case .card(let card): card.copyableText
    case .input, .reading, .failure, .needsSetup, .checking: nil
    }
  }

  /// Return replaces the selection.
  var canReplace: Bool {
    if case .corrected(let correction) = self { correction.canReplace } else { false }
  }
}

/// A finished proofread and which of its changes the user keeps (architecture 6.7, 11.5).
/// A change is a `.changed` run of the diff, numbered from 0; every change starts accepted.
/// The panel changes `accepted` and `current` itself, as the user reviews.
struct Correction: Sendable, Equatable {
  /// Every change the model made, accepted or not.
  var proposed: AppliedEdits
  var accepted: Set<Int>
  /// The change ←, → and Space act on; nil when there are none.
  var current: Int?
  /// There are changes and the selection's field can be written (architecture 4.3).
  var canReplace: Bool
  /// Return was pressed with every change declined, so nothing was replaced; the footer
  /// says why until the next review step.
  var declinedReturn = false

  init(_ applied: AppliedEdits, replaceable: Bool) {
    proposed = applied
    accepted = Set(0..<applied.changeCount)
    current = applied.changeCount > 0 ? 0 : nil
    canReplace = replaceable && applied.changeCount > 0
  }

  var changeCount: Int { proposed.changeCount }

  /// The source with the accepted changes made; replaced, copied and recorded.
  var result: AppliedEdits { proposed.accepting(accepted) }

  var text: String { result.text }

  /// Accepts a declined change and declines an accepted one, and makes it current.
  mutating func toggle(_ change: Int) {
    guard (0..<changeCount).contains(change) else { return }
    if accepted.contains(change) { accepted.remove(change) } else { accepted.insert(change) }
    current = change
    declinedReturn = false
  }

  mutating func toggleCurrent() {
    if let current { toggle(current) }
  }

  /// Moves `current` by `offset` changes, stopping at the first and the last.
  mutating func moveCurrent(by offset: Int) {
    guard changeCount > 0 else { return }
    current = min(max((current ?? 0) + offset, 0), changeCount - 1)
    declinedReturn = false
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
