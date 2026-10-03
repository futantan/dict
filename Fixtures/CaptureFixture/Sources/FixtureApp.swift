// SPDX-License-Identifier: GPL-3.0-or-later
//
// End-to-end test fixture (architecture 14.3). This is an empty shell until M1.5.

import AppKit

@main
@MainActor
final class FixtureApp: NSObject, NSApplicationDelegate {
  private var window: NSWindow?

  static func main() {
    let app = NSApplication.shared
    let delegate = FixtureApp()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "CaptureFixture"
    window.isReleasedWhenClosed = false
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
