// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Testing

@testable import DictApp

@MainActor
struct StatusMenuTests {
  @Test func hasAboutSettingsSeparatorAndQuit() {
    let menu = StatusMenu.make(appName: "Sample")

    #expect(menu.items.count == 4)
    #expect(menu.items[2].isSeparatorItem)
  }

  @Test func settingsItemOpensSettingsWithCommandComma() {
    let settings = StatusMenu.make(appName: "Sample").items[1]

    #expect(settings.action == #selector(AppDelegate.showSettings(_:)))
    #expect(settings.keyEquivalent == ",")
    #expect(settings.keyEquivalentModifierMask == .command)
    #expect(!settings.title.isEmpty)
  }

  @Test func aboutItemShowsAboutPanel() {
    let about = StatusMenu.make(appName: "Sample").items[0]

    #expect(about.action == #selector(AppDelegate.showAbout(_:)))
    #expect(about.title.contains("Sample"))
  }

  @Test func quitItemTerminatesWithCommandQ() {
    let quit = StatusMenu.make(appName: "Sample").items[3]

    #expect(quit.action == #selector(NSApplication.terminate(_:)))
    #expect(quit.keyEquivalent == "q")
    #expect(quit.keyEquivalentModifierMask == .command)
    #expect(quit.title.contains("Sample"))
  }
}
