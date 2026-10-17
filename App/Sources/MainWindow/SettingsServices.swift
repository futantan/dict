// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import ServiceManagement

/// What the settings page needs from the rest of the app beyond `SettingsModel` and the
/// shortcuts. The app delegate fills it in; the gallery and the tests use fixed values, so
/// nothing there registers a login item or opens System Settings.
@MainActor
struct SettingsServices {
  var appName = "Dict"
  var version = ""
  var loginItem = LoginItem.inert
  var accessibilityGranted: () -> Bool = { false }
  var openAccessibilitySettings: () -> Void = {}
  var voice: () -> VoiceChoice = { VoiceChoice(voice: nil, hint: .noVoice) }
  var openVoiceSettings: () -> Void = {}
  /// Nil when this build has no updater.
  var checkForUpdates: (() -> Void)?
  var canCheckForUpdates: () -> Bool = { false }
  /// Applies a change of the Dock or menu bar switch.
  var presenceChanged: (Preferences) -> Void = { _ in }
  /// Asks where to save the Anki export and writes it.
  var export: () -> Void = {}
}

/// 「登录时启动」 through `SMAppService.mainApp`, or a stand-in.
struct LoginItem: Sendable {
  enum Status: Equatable { case off, on, needsApproval }

  var status: @Sendable () -> Status
  /// Throws what the system reports, shown under the switch.
  var setEnabled: @Sendable (Bool) throws -> Void

  static let mainApp = LoginItem(
    status: {
      switch SMAppService.mainApp.status {
      case .enabled: .on
      case .requiresApproval: .needsApproval
      default: .off
      }
    },
    setEnabled: { enabled in
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    })

  /// Off, and switching it does nothing.
  static let inert = LoginItem(status: { .off }, setEnabled: { _ in })
}
