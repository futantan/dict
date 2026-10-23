// SPDX-License-Identifier: GPL-3.0-or-later

/// What the toast says after a replacement (architecture 11.3).
enum ToastMessage: Sendable, Equatable {
  case replaced
  /// The target changed before writing; nothing was written.
  case notReplaced(result: String)
  /// Something was written but reading back cannot confirm it.
  case unconfirmed(clipboardHoldsResult: Bool)
  /// Certainly not written.
  case failed(result: String)

  init(_ outcome: ReplaceOutcome, result: String) {
    switch outcome {
    case .replaced: self = .replaced
    case .stale: self = .notReplaced(result: result)
    case .unconfirmed(let holds): self = .unconfirmed(clipboardHoldsResult: holds)
    case .failed: self = .failed(result: result)
    }
  }

  var text: String {
    switch self {
    case .replaced: WritingStrings.replaced
    case .notReplaced: WritingStrings.notReplaced
    case .unconfirmed(let holds):
      holds ? WritingStrings.clipboardHoldsResult : WritingStrings.unconfirmed
    case .failed: WritingStrings.pasteFailed
    }
  }

  /// The correction the toast offers to copy, when it was not written.
  var copyableResult: String? {
    switch self {
    case .notReplaced(let result), .failed(let result): result
    case .replaced, .unconfirmed: nil
    }
  }

  var isSuccess: Bool { self == .replaced }
}
