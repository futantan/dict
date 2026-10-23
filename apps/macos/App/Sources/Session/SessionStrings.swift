// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Panel wording owned by the session (table `Localizable`).
enum SessionStrings {
  /// A capture failure that is not about permissions.
  static func captureFailure(_ failure: CaptureFailure) -> PanelNotice {
    PanelNotice(
      title: String(
        localized: "Couldn’t read the selection",
        comment: "Panel title when the selected text could not be read"),
      message: failure.message)
  }
}
