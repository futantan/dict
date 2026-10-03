// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?

  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    #if DEBUG
      E2ERunner.startIfRequested()
    #endif
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let identity = AppIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])
    let appName = identity?.name ?? ProcessInfo.processInfo.processName

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(
      systemSymbolName: "character.book.closed", accessibilityDescription: appName)
    item.menu = StatusMenu.make(appName: appName)
    statusItem = item
  }

  @objc func showAbout(_ sender: Any?) {
    NSApp.activate()
    NSApp.orderFrontStandardAboutPanel(sender)
  }
}
