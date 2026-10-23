// SPDX-License-Identifier: GPL-3.0-or-later
//
// Replace contract (architecture 4.2). Shared by every task: change it only through the
// architecture document.

import ApplicationServices

/// A snapshot taken when the Write key fires, before the panel appears.
/// If any part no longer matches later, nothing is written.
struct ReplaceTarget: Sendable {
  let app: TargetApp
  let element: AXElement
  /// The selection; the whole value's range when there is no selection.
  let range: CFRange
  let selectedText: String
  /// The whole value before writing, at most 200 000 UTF-16 units (otherwise not replaceable).
  let valueBefore: String
  /// kAXSelectedText reports itself writable: try the accessibility write first.
  let axWritable: Bool
}

enum ReplaceOutcome: Sendable, Equatable {
  /// Confirmed by reading back: the value changed and the result occurs exactly once more.
  case replaced(via: ReplacePath)
  /// The write or paste went out but reading back cannot confirm it; never retried.
  case unconfirmed(clipboardHoldsResult: Bool)
  /// The target changed; nothing was written.
  case stale(StaleReason)
  /// Certainly not written (for example the paste timed out and the value is unchanged).
  case failed(FailReason)
}
enum ReplacePath: Sendable { case accessibility, paste }
enum StaleReason: Sendable {
  case appChanged, elementChanged, selectionChanged, valueChanged, secureField
}
enum FailReason: Sendable { case pasteNotApplied, noPostEventPermission, clipboardDenied }

@MainActor
protocol ReplaceWriter {
  /// With `rich`, the result keeps the source's formatting (architecture 4.7): it is pasted
  /// as plain text, RTF and HTML together, never written through accessibility.
  func replace(_ target: ReplaceTarget, with result: String, rich: RichPayload?) async
    -> ReplaceOutcome
}

extension ReplaceWriter {
  func replace(_ target: ReplaceTarget, with result: String) async -> ReplaceOutcome {
    await replace(target, with: result, rich: nil)
  }
}
