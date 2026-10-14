// SPDX-License-Identifier: GPL-3.0-or-later

import ApplicationServices
import DictCore
import Foundation

/// The target field as read at one moment.
struct FieldReading: Sendable {
  /// The target element is still the app's focused element.
  var isFocused: Bool
  var isSecure: Bool
  var range: CFRange?
  var selectedText: String?
  var value: String?
}

/// What `SystemReplaceWriter` needs from the system: accessibility, the clipboard and key
/// posting (architecture 4.2). Tests script a fake.
@MainActor
protocol ReplaceSystem {
  func frontmostPID() -> pid_t?
  /// Nil when the element no longer answers.
  func read(_ target: ReplaceTarget) async -> FieldReading?
  func writeSelectedText(_ text: String, into target: ReplaceTarget) async
  /// Event posting is allowed and the target does not hold secure input.
  func canPostKeys(to target: ReplaceTarget) -> Bool
  var clipboardDenied: Bool { get }
  var clipboardChangeCount: Int { get }
  func snapshotClipboard() -> ClipboardSnapshot
  /// Writes `text`, with RTF and HTML beside it when `rich` is given, marked transient;
  /// returns the new change count.
  func writeClipboard(_ text: String, rich: RichPayload?) -> Int
  func restoreClipboard(_ snapshot: ClipboardSnapshot)
  func postPaste(to pid: pid_t)
  func sleep(_ duration: Duration) async
}

/// Writes a result in place of the snapshotted selection (architecture 4.4): an
/// accessibility write first, checked by reading the field back, then one paste. The target
/// is checked again before each, so nothing lands anywhere but where the user selected, and
/// a write that took effect late is never followed by a paste. A result with formatting
/// (architecture 4.7) skips the accessibility write, which takes plain text only; when it
/// cannot be pasted, it is written as plain text instead.
@MainActor
struct SystemReplaceWriter: ReplaceWriter {
  let system: any ReplaceSystem

  static let pollInterval: Duration = .milliseconds(20)
  static let checkWindow: Duration = .milliseconds(300)
  static let accessibilityReadBack: Duration = .milliseconds(300)
  static let pasteReadBack: Duration = .seconds(1)

  func replace(_ target: ReplaceTarget, with result: String, rich: RichPayload?) async
    -> ReplaceOutcome
  {
    if let stale = await check(target) { return .stale(stale) }

    var rich = rich
    if rich != nil, !system.canPostKeys(to: target) || system.clipboardDenied {
      Log.replace.info("formatting cannot be pasted here: replacing with plain text")
      rich = nil
    }
    if target.axWritable && rich == nil {
      await system.writeSelectedText(result, into: target)
      switch await readBack(target, result: result, window: Self.accessibilityReadBack) {
      case .confirmed: return .replaced(via: .accessibility)
      case .duplicated, .changedUnexpectedly: return .unconfirmed(clipboardHoldsResult: false)
      case .unchanged: break
      }
      // Chromium applies writes asynchronously; one that lands later than this moves the
      // selection, so the check fails instead of pasting a second copy.
      if let stale = await check(target) { return .stale(stale) }
    }

    guard system.canPostKeys(to: target) else { return .failed(.noPostEventPermission) }
    guard !system.clipboardDenied else { return .failed(.clipboardDenied) }
    let snapshot = system.snapshotClipboard()
    let written = system.writeClipboard(result, rich: rich)
    system.postPaste(to: target.app.pid)
    let readBack = await readBack(target, result: result, window: Self.pasteReadBack)
    let clipboardIsOurs = system.clipboardChangeCount == written
    switch readBack {
    case .confirmed:
      if clipboardIsOurs { system.restoreClipboard(snapshot) }
      return .replaced(via: .paste)
    case .unchanged:
      if clipboardIsOurs { system.restoreClipboard(snapshot) }
      return .failed(.pasteNotApplied)
    case .duplicated, .changedUnexpectedly:
      // The app may still read the clipboard; putting the old content back now could
      // paste that instead.
      return .unconfirmed(clipboardHoldsResult: clipboardIsOurs)
    }
  }

  /// Waits up to 300 ms for the target to be as snapshotted: the app in front, the element
  /// focused and not secure, the selection and the whole value unchanged. Returns why not.
  private func check(_ target: ReplaceTarget) async -> StaleReason? {
    var waited: Duration = .zero
    while true {
      guard let reason = await staleReason(target) else { return nil }
      guard waited < Self.checkWindow else { return reason }
      await system.sleep(Self.pollInterval)
      waited += Self.pollInterval
    }
  }

  private func staleReason(_ target: ReplaceTarget) async -> StaleReason? {
    guard system.frontmostPID() == target.app.pid else { return .appChanged }
    guard let field = await system.read(target), field.isFocused else { return .elementChanged }
    if field.isSecure { return .secureField }
    guard let range = field.range, range.location == target.range.location,
      range.length == target.range.length, field.selectedText == target.selectedText
    else { return .selectionChanged }
    guard field.value == target.valueBefore else { return .valueChanged }
    return nil
  }

  /// Reads the value every 20 ms until it changes or `window` ends.
  private func readBack(_ target: ReplaceTarget, result: String, window: Duration) async
    -> ReadBack
  {
    var waited: Duration = .zero
    while true {
      if let value = await system.read(target)?.value {
        let judged = judge(target, value, result)
        if judged != .unchanged { return judged }
      }
      guard waited < window else { return .unchanged }
      await system.sleep(Self.pollInterval)
      waited += Self.pollInterval
    }
  }

  private func judge(_ target: ReplaceTarget, _ value: String, _ result: String) -> ReadBack {
    replacementConfirmed(
      before: target.valueBefore, after: value, original: target.selectedText, result: result)
  }
}
