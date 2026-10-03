// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

extension NSApplication {
  /// Makes Dict the active app so the window just ordered front becomes key.
  ///
  /// Since macOS 14 activation is cooperative, and `activate()` alone is refused for Dict:
  /// as an `LSUIElement` app it is not brought forward when launched with `open`, and its
  /// status menu does not activate it either, so nothing ever yields to it and its windows
  /// stay behind the front app. Naming the front app as the one yielding is honored
  /// (checked on macOS 26 by `make window-test`).
  func activateFromFrontApp() {
    let current = NSRunningApplication.current
    if let front = NSWorkspace.shared.frontmostApplication, front != current {
      _ = current.activate(from: front, options: [])
    } else {
      activate()
    }
  }
}
