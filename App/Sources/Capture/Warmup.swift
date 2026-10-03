// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices

/// The setting "turn on accessibility support for Chrome and Electron apps" (architecture 3.3).
/// The defaults follow the open question 16.1 #1's suggestion: on for Chromium browsers, off for
/// Electron apps, until the manager decides; the settings window will own the switches.
struct AccessibilitySupport: Equatable, Sendable {
  static let chromiumKey = "AccessibilitySupportChromium"
  static let electronKey = "AccessibilitySupportElectron"

  var chromium: Bool
  var electron: Bool

  init(chromium: Bool, electron: Bool) {
    self.chromium = chromium
    self.electron = electron
  }

  init(defaults: UserDefaults) {
    chromium = defaults.object(forKey: Self.chromiumKey) as? Bool ?? true
    electron = defaults.object(forKey: Self.electronKey) as? Bool ?? false
  }
}

/// The attribute that makes an app build its full accessibility tree, if it needs one and the
/// user allows it. Chrome honours only AXEnhancedUserInterface; Electron only
/// AXManualAccessibility.
func warmupAttribute(for kind: AppKind, support: AccessibilitySupport) -> String? {
  switch kind {
  case .chromium: support.chromium ? "AXEnhancedUserInterface" : nil
  case .electron: support.electron ? "AXManualAccessibility" : nil
  case .native, .terminal, .ownApp: nil
  }
}

enum WarmupState: Equatable, Sendable {
  /// The app needs no attribute, or the user turned support off.
  case notNeeded
  /// The attribute was already on (by us earlier, or by another assistive app).
  case warm
  /// We turned it on just now; the tree takes about 2 s to be readable.
  case justEnabled
}

/// Turns the attribute on when a Chromium or Electron app comes to the front, keeps it on while
/// Dict runs, and puts the original value back when Dict quits.
@MainActor
final class AccessibilityWarmer {
  /// Electron builds its tree on the first write but loads text only after a second one.
  static let electronRewriteDelay: Duration = .milliseconds(2500)

  private struct Entry {
    let attribute: String
    /// False when we turned the attribute on and must turn it off at quit.
    var restoreTo: Bool?
  }

  private let queue: AXQueue
  private let resolver: TargetAppResolver
  private let support: () -> AccessibilitySupport
  private var entries: [TargetApp.InstanceKey: Entry] = [:]
  private var observers: [any NSObjectProtocol] = []

  init(
    queue: AXQueue, resolver: TargetAppResolver,
    support: @escaping () -> AccessibilitySupport = { AccessibilitySupport(defaults: .standard) }
  ) {
    self.queue = queue
    self.resolver = resolver
    self.support = support
  }

  /// Starts watching app activation and quit; warms the current front app right away.
  func start() {
    guard observers.isEmpty else { return }
    let workspace = NSWorkspace.shared.notificationCenter
    observers.append(
      workspace.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
      ) { [weak self] note in
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        MainActor.assumeIsolated { self?.warm(running: app) }
      })
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.restoreAll() }
      })
    warm(running: NSWorkspace.shared.frontmostApplication)
  }

  private func warm(running app: NSRunningApplication?) {
    guard let app else { return }
    let target = resolver.resolve(app)
    Task { _ = await warm(target) }
  }

  /// Makes sure the attribute is on for `app`; says whether the tree should already be built.
  func warm(_ app: TargetApp) async -> WarmupState {
    guard let attribute = warmupAttribute(for: app.kind, support: support()) else {
      return .notNeeded
    }
    guard entries[app.instanceKey] == nil else { return .warm }
    entries[app.instanceKey] = Entry(attribute: attribute, restoreTo: nil)

    let pid = app.pid
    let wasOn = await queue.run { () -> Bool in
      let element = AX.application(pid)
      if AX.bool(element, attribute) == true { return true }
      // Chrome answers -25208 but the attribute does take effect; judge by reading back.
      _ = AX.set(element, attribute, kCFBooleanTrue)
      return false
    }
    entries[app.instanceKey]?.restoreTo = wasOn ? nil : false
    Log.capture.info(
      "warm-up \(attribute, privacy: .public) for \(app.bundleID ?? "?", privacy: .public): \(wasOn ? "already on" : "turned on", privacy: .public)"
    )

    if app.kind == .electron, !wasOn {
      let queue = self.queue
      Task {
        try? await Task.sleep(for: Self.electronRewriteDelay)
        await queue.run { _ = AX.set(AX.application(pid), attribute, kCFBooleanTrue) }
      }
    }
    return wasOn ? .warm : .justEnabled
  }

  /// Puts back every attribute we turned on, for apps that are still running.
  func restoreAll() {
    for (key, entry) in entries {
      guard let original = entry.restoreTo,
        let app = NSRunningApplication(processIdentifier: key.pid), app.launchDate == key.launchDate
      else { continue }
      let attribute = entry.attribute
      let pid = key.pid
      let error = queue.runAndWait {
        AX.set(AX.application(pid), attribute, original ? kCFBooleanTrue : kCFBooleanFalse)
      }
      Log.capture.info(
        "restored \(attribute, privacy: .public) for \(app.bundleIdentifier ?? "?", privacy: .public): \(error.rawValue, privacy: .public)"
      )
    }
    entries.removeAll()
  }
}
