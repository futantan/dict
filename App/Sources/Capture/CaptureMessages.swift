// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

extension CaptureFailure {
  /// What the panel tells the user. Nil for the permission cases, whose explanation and
  /// shortcut to System Settings belong to the permission guide, and for Dict itself.
  var message: String? {
    switch self {
    case .noAccessibilityPermission, .noPostEventPermission, .ownApp:
      return nil
    case .secureField:
      return String(
        localized: "Dict never reads password fields.", table: "Capture",
        comment: "The focused field is a password field")
    case .secureInput(let holder?):
      return String(
        localized: "\(holder) has turned on secure input, so Dict cannot copy from it.",
        table: "Capture", comment: "Secure input is on in the named app; the copy fallback stops")
    case .secureInput(nil):
      return String(
        localized: "An app has turned on secure input, so Dict cannot copy from it.",
        table: "Capture", comment: "Secure input is on in an unknown app; the copy fallback stops")
    case .clipboardDenied:
      return String(
        localized: "Dict is not allowed to read the clipboard. Copy the text and paste it here.",
        table: "Capture", comment: "The clipboard privacy setting denies Dict")
    case .nothingSelected:
      return String(
        localized: "Nothing is selected.", table: "Capture",
        comment: "The focused field has no selection")
    case .unreadable:
      return String(
        localized: "Dict could not read the selection in this app. Copy it and paste it here.",
        table: "Capture", comment: "Neither accessibility nor copying gave the selected text")
    }
  }
}
