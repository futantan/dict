// SPDX-License-Identifier: GPL-3.0-or-later
//
// Capture contract (architecture 3.2). Shared by every task: change it only through the
// architecture document.

import ApplicationServices
import DictCore
import Foundation

/// The app text is captured from. `launchDate` and `pid` together key the warm-up cache,
/// so a reused pid is not mistaken for the same app instance.
struct TargetApp: Sendable, Equatable {
  let pid: pid_t
  let bundleID: String?
  let launchDate: Date?
  let kind: AppKind
}

enum AppKind: Sendable, Equatable {
  /// Native AppKit and WebKit (Safari, TextEdit, Notes).
  case native
  /// Chrome, Edge, Brave, Arc and others: write AXEnhancedUserInterface.
  case chromium
  /// VS Code, Slack and others: write AXManualAccessibility, again once the tree is built.
  case electron
  /// Terminals: readable, never replaced or pasted into.
  case terminal
  /// Dict itself.
  case ownApp
}

/// Carries an accessibility element across queues.
/// An AXUIElement is an immutable reference into another process; every call on it is an
/// inter-process message, and calls are only made on the accessibility queue, so it is
/// treated as Sendable.
struct AXElement: @unchecked Sendable, Equatable {
  let raw: AXUIElement
  static func == (a: AXElement, b: AXElement) -> Bool { CFEqual(a.raw, b.raw) }
}

enum CaptureSource: Sendable, Equatable {
  /// Read through accessibility; whether it is replaceable depends on `Selection.target`.
  case accessibility
  /// Pressed the menu bar Copy item, read through the clipboard.
  case menuCopy
  /// Posted ⌘C to the target process, read through the clipboard.
  case keyCopy
  /// Recognised from a screenshot; read-only.
  case ocr
  /// Typed by the user into the panel; read-only.
  case typed
}

struct Selection: Sendable {
  let text: String
  let source: CaptureSource
  let app: TargetApp?
  /// Screen coordinates (Cocoa, origin at the bottom left); nil when unavailable.
  let bounds: CGRect?
  let context: ContextSentence?
  /// Present only when the selection can be replaced (architecture 4.3).
  let target: ReplaceTarget?
}

enum CaptureFailure: Error, Sendable, Equatable {
  case noAccessibilityPermission
  case noPostEventPermission
  /// The focused element is a password field.
  case secureField
  /// Another app holds secure input, and the fallback would have to post keys into it.
  case secureInput(holder: String?)
  /// The clipboard privacy setting denies access.
  case clipboardDenied
  case ownApp
  case nothingSelected(fieldText: String?)
  case unreadable(axError: Int32?)
}

enum ClipboardPolicy: Sendable { case never, allowed }

@MainActor
protocol SelectionReader {
  /// The hotkey path passes `.allowed`; the selection-icon path passes `.never`.
  func capture(policy: ClipboardPolicy) async -> Result<Selection, CaptureFailure>
}
