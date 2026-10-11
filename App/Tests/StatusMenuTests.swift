// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Testing

@testable import DictApp

@MainActor
struct StatusMenuTests {
  /// Architecture 11.4: Settings comes before About and Check for Updates, and Quit is last.
  @Test func hasSettingsAboutUpdatesSeparatorAndQuit() {
    let menu = StatusMenu.make(appName: "Sample")

    #expect(menu.items.count == 5)
    #expect(menu.items[3].isSeparatorItem)
  }

  @Test func settingsItemOpensSettingsWithCommandComma() {
    let settings = StatusMenu.make(appName: "Sample").items[0]

    #expect(settings.action == #selector(AppDelegate.showSettings(_:)))
    #expect(settings.keyEquivalent == ",")
    #expect(settings.keyEquivalentModifierMask == .command)
    #expect(!settings.title.isEmpty)
  }

  @Test func aboutItemShowsAboutPanel() {
    let about = StatusMenu.make(appName: "Sample").items[1]

    #expect(about.action == #selector(AppDelegate.showAbout(_:)))
    #expect(about.title.contains("Sample"))
  }

  @Test func checkForUpdatesItemAsksTheUpdater() {
    let check = StatusMenu.make(appName: "Sample").items[2]

    #expect(check.action == #selector(AppDelegate.checkForUpdates(_:)))
    #expect(check.keyEquivalent.isEmpty)
    #expect(!check.title.isEmpty)
  }

  @Test func quitItemTerminatesWithCommandQ() {
    let quit = StatusMenu.make(appName: "Sample").items[4]

    #expect(quit.action == #selector(NSApplication.terminate(_:)))
    #expect(quit.keyEquivalent == "q")
    #expect(quit.keyEquivalentModifierMask == .command)
    #expect(quit.title.contains("Sample"))
  }

  @Test func shortcutWarningsComeFirstAndOpenTheShortcutSettings() {
    let warning = HotkeyRole.read.warning(.registrationFailed(-9878))
    let menu = StatusMenu.make(appName: "Sample", warnings: [warning])

    #expect(menu.items.count == 7)
    #expect(menu.items[0].title == warning)
    #expect(menu.items[0].action == #selector(AppDelegate.showShortcutSettings(_:)))
    #expect(menu.items[1].isSeparatorItem)
    #expect(menu.items[2].action == #selector(AppDelegate.showSettings(_:)))
  }
}
