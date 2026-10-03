// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Testing

@testable import DictApp

@MainActor
struct StatusMenuTests {
  @Test func hasAboutSeparatorAndQuit() {
    let menu = StatusMenu.make(appName: "Sample")

    #expect(menu.items.count == 3)
    #expect(menu.items[1].isSeparatorItem)
  }

  @Test func aboutItemShowsAboutPanel() {
    let about = StatusMenu.make(appName: "Sample").items[0]

    #expect(about.action == #selector(AppDelegate.showAbout(_:)))
    #expect(about.title.contains("Sample"))
  }

  @Test func quitItemTerminatesWithCommandQ() {
    let quit = StatusMenu.make(appName: "Sample").items[2]

    #expect(quit.action == #selector(NSApplication.terminate(_:)))
    #expect(quit.keyEquivalent == "q")
    #expect(quit.keyEquivalentModifierMask == .command)
    #expect(quit.title.contains("Sample"))
  }
}
