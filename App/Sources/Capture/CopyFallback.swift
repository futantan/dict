// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Whether the hotkey path should copy after the accessibility read failed (architecture 3.6).
/// The selection-icon path (`.never`) never touches the clipboard.
func needsCopyFallback(
  after failure: CaptureFailure, kind: AppKind, policy: ClipboardPolicy
) -> Bool {
  guard policy == .allowed else { return false }
  switch failure {
  case .unreadable: return true
  // Chromium and Electron trees may not hold the text yet.
  case .nothingSelected: return kind == .chromium || kind == .electron
  default: return false
  }
}

/// An editor that copies the current line when nothing is selected must not count as a
/// selection. With the field text, a copy equal to one of its lines is such a copy; without
/// it, a single line ending in a newline is.
func isWholeLineCopy(_ copied: String, fieldText: String?) -> Bool {
  // "\r\n" is a single Character, so dropping one Character drops either line ending.
  let line = copied.last?.isNewline == true ? String(copied.dropLast()) : copied
  guard !line.isEmpty, !line.contains(where: \.isNewline) else { return false }
  guard let fieldText else { return line != copied }
  return fieldText.components(separatedBy: .newlines).contains(line)
}

enum MenuCopyState: Equatable, Sendable {
  case enabled
  /// The item exists but is disabled: there is no selection.
  case disabled
  case notFound
}

struct CopiedSelection: Equatable, Sendable {
  let text: String
  let source: CaptureSource
}

/// The copy fallback: the menu bar Copy item, then ⌘C posted to the target, read through the
/// clipboard, which is always put back. The hooks are injected so the order can be tested.
@MainActor
struct CopyFallback {
  let clipboard: ClipboardGateway
  let findMenuCopy: () async -> MenuCopyState
  /// Returns the accessibility error code, or nil when the press succeeded.
  let pressMenuCopy: () async -> Int32?
  let canPostEvents: () -> Bool
  /// The failure to report when posting keys would go into a secure input holder.
  let secureInputBlock: () -> CaptureFailure?
  let postCopyKey: () -> Void
  var copyTimeout: Duration = .milliseconds(300)
  var lateCopyWindow: Duration = .seconds(1)

  /// Runs after `first` failed; on any failure of its own, `first` is kept unless the
  /// fallback learned something more specific.
  func run(
    after first: CaptureFailure, accessDenied: Bool = false
  ) async -> Result<CopiedSelection, CaptureFailure> {
    if accessDenied { return .failure(.clipboardDenied) }
    var fieldText: String?
    if case .nothingSelected(let text) = first { fieldText = text }

    var snapshot: ClipboardSnapshot?
    switch await findMenuCopy() {
    case .disabled:
      return .failure(.nothingSelected(fieldText: fieldText))
    case .enabled:
      let taken = clipboard.snapshot()
      snapshot = taken
      if await pressMenuCopy() == nil {
        return await finish(taken, source: .menuCopy, first: first, fieldText: fieldText)
      }
    case .notFound:
      break
    }

    guard canPostEvents() else { return .failure(.noPostEventPermission) }
    if let blocked = secureInputBlock() { return .failure(blocked) }
    let taken = snapshot ?? clipboard.snapshot()
    postCopyKey()
    return await finish(taken, source: .keyCopy, first: first, fieldText: fieldText)
  }

  private func finish(
    _ snapshot: ClipboardSnapshot, source: CaptureSource, first: CaptureFailure,
    fieldText: String?
  ) async -> Result<CopiedSelection, CaptureFailure> {
    let copied = await clipboard.waitForCopy(since: snapshot.changeCount, timeout: copyTimeout)
    let content = copied ? clipboard.copiedContent() : .none
    clipboard.restore(snapshot)
    guard copied else {
      let clipboard = self.clipboard
      let window = lateCopyWindow
      Task { await clipboard.undoLateCopy(of: snapshot, window: window) }
      return .failure(first)
    }
    guard case .text(let text) = content,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !isWholeLineCopy(text, fieldText: fieldText)
    else { return .failure(.nothingSelected(fieldText: fieldText)) }
    return .success(CopiedSelection(text: text, source: source))
  }
}
