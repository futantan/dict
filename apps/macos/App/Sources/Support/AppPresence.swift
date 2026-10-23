// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore

/// Where Dict shows itself (Design/main-app/README.md): a Dock icon makes it a regular app
/// that ⌘Tab reaches, the menu bar icon is the status item.
///
/// The bundle stays `LSUIElement`, so Dict starts as an agent and becomes regular here when
/// the Dock icon is on: the unit test host, which is the app, never gets a Dock icon or
/// takes focus, and turning the icon off takes effect from launch without a flash.
///
/// The result panel is a non-activating panel either way: showing it never makes Dict the
/// active app, so the app the user is in keeps the focus.
struct AppPresence: Equatable {
  var activationPolicy: NSApplication.ActivationPolicy
  var showsStatusItem: Bool

  init(_ preferences: Preferences) {
    activationPolicy = preferences.showsDockIcon ? .regular : .accessory
    showsStatusItem = preferences.showsMenuBarIcon
  }
}
