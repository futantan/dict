// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The panel content for permission problems and the buttons it offers (architecture 3.8,
/// 11.1). The session coordinator shows `notice(for:)` in the panel's needs-setup phase and
/// passes `PanelController.onAction` ids to `perform(_:)`.
///
/// Nothing here asks macOS for a permission on its own. Only when the user clicks "Open
/// System Settings" does the guide call `AXIsProcessTrustedWithOptions` with the prompt
/// option, which adds Dict to the Accessibility list, before opening System Settings
/// (architecture 11.1). The user turns Dict on there and `PermissionMonitor` notices.
@MainActor
struct PermissionGuide {
  /// The ids of the buttons in permission notices.
  enum ActionID {
    static let openSettings = "permissions.openSettings"
    static let copyResetCommand = "permissions.copyResetCommand"
  }

  /// The names the user sees in System Settings, which differ between Debug and Release.
  struct AppIdentity: Sendable, Equatable {
    var name: String
    var bundleID: String

    static var current: AppIdentity {
      let info = Bundle.main.infoDictionary ?? [:]
      return AppIdentity(
        name: info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String
          ?? "Dict",
        bundleID: Bundle.main.bundleIdentifier ?? "au.ibra.dict")
    }
  }

  /// Privacy & Security → Accessibility, which lists both permissions. The string is a
  /// valid URL; the fallback only keeps the type non-optional and opens System Settings.
  nonisolated static let settingsURL =
    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    ?? URL(fileURLWithPath: "/System/Applications/System Settings.app")

  let app: AppIdentity
  private let openURL: (URL) -> Void
  private let copy: (String) -> Void
  private let requestTrust: () -> Void

  init(
    app: AppIdentity = .current,
    openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
    copy: @escaping (String) -> Void = PermissionGuide.copyToPasteboard,
    requestTrust: @escaping () -> Void = PermissionGuide.registerForAccessibility
  ) {
    self.app = app
    self.openURL = openURL
    self.copy = copy
    self.requestTrust = requestTrust
  }

  func notice(for issue: PermissionIssue) -> PanelNotice {
    Self.notice(for: issue, app: app)
  }

  /// Handles a notice button. Returns false for ids that are not permission actions, so
  /// the caller can handle its own.
  func perform(_ actionID: PanelAction.ID) -> Bool {
    switch actionID {
    case ActionID.openSettings:
      Log.ui.info("permissions: opening System Settings")
      requestTrust()
      openURL(Self.settingsURL)
    case ActionID.copyResetCommand:
      copy(Self.resetCommand(app))
    default:
      return false
    }
    return true
  }

  // MARK: - Content

  /// Resets the stale grant; architecture 3.8.
  nonisolated static func resetCommand(_ app: AppIdentity) -> String {
    "tccutil reset Accessibility \(app.bundleID)"
  }

  nonisolated static func notice(for issue: PermissionIssue, app: AppIdentity) -> PanelNotice {
    let name = app.name
    let open = PanelAction(
      id: ActionID.openSettings,
      title: String(
        localized: "Open System Settings", table: "Permissions",
        comment: "Button that opens the Accessibility pane of System Settings"),
      isDefault: true)
    switch issue {
    case .missing(.accessibility):
      return PanelNotice(
        symbol: "hand.raised.fill",
        title: String(
          localized: "Accessibility permission needed", table: "Permissions",
          comment: "Panel title when the app is not allowed to use accessibility"),
        message: String(
          localized: """
            \(name) needs Accessibility permission to read the text you select. Turn on \
            \(name) in System Settings → Privacy & Security → Accessibility.
            """, table: "Permissions",
          comment: "Panel message when accessibility is off; both arguments are the app name"),
        actions: [open])
    case .missing(.postEvent):
      return PanelNotice(
        symbol: "keyboard",
        title: String(
          localized: "Permission to send keystrokes needed", table: "Permissions",
          comment: "Panel title when the app may not post ⌘C or ⌘V to other apps"),
        message: String(
          localized: """
            \(name) sends ⌘C and ⌘V to apps it can’t read directly. In System Settings → \
            Privacy & Security → Accessibility, turn on \(name), or turn it off and on again.
            """, table: "Permissions",
          comment:
            "Panel message when posting keystrokes is not allowed; both arguments are the app name"),
        actions: [open])
    case .staleAccessibility:
      let command = resetCommand(app)
      return PanelNotice(
        symbol: "exclamationmark.lock.fill",
        title: String(
          localized: "Accessibility permission needs a reset", table: "Permissions",
          comment: "Panel title when System Settings shows the app as allowed but macOS refuses it"),
        message: String(
          localized: """
            System Settings shows \(name) as allowed, but macOS no longer accepts it, usually \
            after an update. Remove \(name) from the Accessibility list and turn it on again, \
            or run this in Terminal: \(command)
            """, table: "Permissions",
          comment:
            "Panel message for a stale accessibility grant; the first two arguments are the app name, the last is a Terminal command"
        ),
        actions: [
          PanelAction(
            id: ActionID.copyResetCommand,
            title: String(
              localized: "Copy Command", table: "Permissions",
              comment: "Button that copies the Terminal command that resets the permission")),
          open,
        ])
    }
  }

  /// Adds Dict to the Accessibility list in System Settings so the user only has to turn it
  /// on. The prompt option may show the system's alert, so this runs only from a click.
  nonisolated static func registerForAccessibility() {
    guard !AXIsProcessTrusted() else { return }
    // The value of `kAXTrustedCheckOptionPrompt`, a global var Swift 6 will not read.
    let options = ["AXTrustedCheckOptionPrompt": true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
  }

  nonisolated static func copyToPasteboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }
}
