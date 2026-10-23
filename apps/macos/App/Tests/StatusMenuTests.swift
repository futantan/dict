// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Testing

@testable import DictApp

@MainActor
struct StatusMenuTests {
  /// Architecture 11.4, with the main window first: Open, Settings, About, Check for
  /// Updates, and Quit last.
  @Test func hasOpenSettingsAboutUpdatesSeparatorAndQuit() {
    let menu = StatusMenu.make(appName: "Sample")

    #expect(menu.items.count == 6)
    #expect(menu.items[4].isSeparatorItem)
  }

  @Test func openItemShowsTheMainWindow() {
    let open = StatusMenu.make(appName: "Sample").items[0]

    #expect(open.action == #selector(AppDelegate.showMainWindow(_:)))
    #expect(open.title.contains("Sample"))
  }

  @Test func settingsItemOpensSettingsWithCommandComma() {
    let settings = StatusMenu.make(appName: "Sample").items[1]

    #expect(settings.action == #selector(AppDelegate.showSettings(_:)))
    #expect(settings.keyEquivalent == ",")
    #expect(settings.keyEquivalentModifierMask == .command)
    #expect(!settings.title.isEmpty)
  }

  @Test func aboutItemShowsAboutPanel() {
    let about = StatusMenu.make(appName: "Sample").items[2]

    #expect(about.action == #selector(AppDelegate.showAbout(_:)))
    #expect(about.title.contains("Sample"))
  }

  @Test func checkForUpdatesItemAsksTheUpdater() {
    let check = StatusMenu.make(appName: "Sample").items[3]

    #expect(check.action == #selector(AppDelegate.checkForUpdates(_:)))
    #expect(check.keyEquivalent.isEmpty)
    #expect(!check.title.isEmpty)
  }

  @Test func quitItemTerminatesWithCommandQ() {
    let quit = StatusMenu.make(appName: "Sample").items[5]

    #expect(quit.action == #selector(NSApplication.terminate(_:)))
    #expect(quit.keyEquivalent == "q")
    #expect(quit.keyEquivalentModifierMask == .command)
    #expect(quit.title.contains("Sample"))
  }

  @Test func shortcutWarningsComeFirstAndOpenTheShortcutSettings() {
    let warning = HotkeyRole.read.warning(.registrationFailed(-9878))
    let menu = StatusMenu.make(appName: "Sample", warnings: [warning])

    #expect(menu.items.count == 8)
    #expect(menu.items[0].title == warning)
    #expect(menu.items[0].action == #selector(AppDelegate.showShortcutSettings(_:)))
    #expect(menu.items[1].isSeparatorItem)
    #expect(menu.items[2].action == #selector(AppDelegate.showMainWindow(_:)))
  }

  /// The main menu has the Edit menu's key equivalents, which text fields depend on, and ⌘,
  /// for Settings.
  @Test func mainMenuCarriesEditingAndSettingsKeys() {
    let menu = MainMenu.make(appName: "Sample")
    let items = menu.items.flatMap { $0.submenu?.items ?? [] }
    for (key, action) in [
      ("c", #selector(NSText.copy(_:))), ("v", #selector(NSText.paste(_:))),
      ("a", #selector(NSText.selectAll(_:))), ("x", #selector(NSText.cut(_:))),
      (",", #selector(AppDelegate.showSettings(_:))),
      ("w", #selector(NSWindow.performClose(_:))),
      ("q", #selector(NSApplication.terminate(_:))),
    ] {
      #expect(items.contains { $0.keyEquivalent == key && $0.action == action }, "\(key)")
    }
  }
}
