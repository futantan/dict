// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The menu bar's menus while Dict is the active app. Besides naming the app, they carry
/// the key equivalents text fields need: without an Edit menu ⌘C, ⌘V, ⌘A and ⌘Z do nothing
/// in the main window.
@MainActor
enum MainMenu {
  static func make(appName: String) -> NSMenu {
    let menu = NSMenu()
    menu.addItem(submenu(appMenu(appName: appName), title: appName))
    menu.addItem(submenu(editMenu(), title: editTitle))
    let window = windowMenu(appName: appName)
    menu.addItem(submenu(window, title: windowTitle))
    NSApp.windowsMenu = window
    return menu
  }

  private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
    menu.title = title
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.submenu = menu
    return item
  }

  private static func appMenu(appName: String) -> NSMenu {
    let menu = NSMenu()
    menu.addItem(
      withTitle: String(
        localized: "About \(appName)", comment: "Menu item that opens the About panel"),
      action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
    menu.addItem(
      withTitle: String(
        localized: "Check for Updates…", comment: "Menu item that checks for a new version"),
      action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: String(
        localized: "Settings…", table: "Settings", comment: "Menu item that opens Settings"),
      action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: String(localized: "Hide \(appName)", comment: "Menu item that hides the app"),
      action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    let others = menu.addItem(
      withTitle: String(localized: "Hide Others", comment: "Menu item that hides other apps"),
      action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
    others.keyEquivalentModifierMask = [.command, .option]
    menu.addItem(
      withTitle: String(localized: "Show All", comment: "Menu item that shows all apps"),
      action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: String(localized: "Quit \(appName)", comment: "Menu item that quits the app"),
      action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    return menu
  }

  private static let editTitle = String(localized: "Edit", comment: "Menu title")
  private static let windowTitle = String(localized: "Window", comment: "Menu title")

  private static func editMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(
      withTitle: String(localized: "Undo", comment: "Edit menu item"),
      action: Selector(("undo:")), keyEquivalent: "z")
    let redo = menu.addItem(
      withTitle: String(localized: "Redo", comment: "Edit menu item"),
      action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    menu.addItem(.separator())
    menu.addItem(
      withTitle: String(localized: "Cut", comment: "Edit menu item"),
      action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    menu.addItem(
      withTitle: String(localized: "Copy", comment: "Edit menu item"),
      action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    menu.addItem(
      withTitle: String(localized: "Paste", comment: "Edit menu item"),
      action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    menu.addItem(
      withTitle: String(localized: "Select All", comment: "Edit menu item"),
      action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    return menu
  }

  private static func windowMenu(appName: String) -> NSMenu {
    let menu = NSMenu()
    menu.addItem(
      withTitle: String(localized: "Minimize", comment: "Window menu item"),
      action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    menu.addItem(
      withTitle: String(localized: "Zoom", comment: "Window menu item"),
      action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    menu.addItem(
      withTitle: String(localized: "Close", comment: "Window menu item"),
      action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: StatusMenu.openTitle(appName), action: #selector(AppDelegate.showMainWindow(_:)),
      keyEquivalent: "0")
    return menu
  }
}
