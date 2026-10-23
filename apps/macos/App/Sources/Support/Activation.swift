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

/// Gives focus back to the app that was in front before one of Dict's windows opened, once
/// that window closes. Without a Dock icon Dict has no other windows, so without this it
/// stays the active app with nothing to type into until the user clicks somewhere.
@MainActor
final class FocusReturn {
  private var previous: NSRunningApplication?

  /// Call before showing the window. Showing it again while Dict is in front keeps the app
  /// remembered first.
  func remember() {
    guard let front = NSWorkspace.shared.frontmostApplication, front != .current else { return }
    previous = front
  }

  /// Call when `window` closes. Does nothing if the user already moved to another app or
  /// another of Dict's windows stays open.
  func restore(closing window: NSWindow) {
    defer { previous = nil }
    guard let previous, !previous.isTerminated, NSApp.isActive,
      !NSApp.windows.contains(where: { $0 !== window && $0.isVisible && $0.canBecomeMain })
    else { return }
    _ = previous.activate(from: .current, options: [])
  }
}
