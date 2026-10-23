// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Keeps the permission state current so a grant takes effect without restarting Dict
/// (architecture 3.8).
///
/// The state is re-read when the caller asks (the panel appears, the settings window
/// becomes key) and 300 ms after the distributed notification `com.apple.accessibility.api`,
/// because `AXIsProcessTrusted()` may not have changed yet when it arrives.
@MainActor
final class PermissionMonitor {
  static let accessibilityChanged = Notification.Name("com.apple.accessibility.api")

  /// Called when a read differs from the previous one, with the permissions that were
  /// just turned on; the session coordinator resumes whatever was waiting for them.
  var onChange: (PermissionStatus, Set<Permission>) -> Void = { _, _ in }

  private(set) var status: PermissionStatus
  private let checker: any PermissionChecker
  private let delay: Duration
  private var observer: (any NSObjectProtocol)?
  private var pendingRead: Task<Void, Never>?

  init(
    checker: any PermissionChecker = SystemPermissionChecker(), delay: Duration = .milliseconds(300)
  ) {
    self.checker = checker
    self.delay = delay
    status = checker.status()
  }

  /// Starts listening for System Settings changes.
  func start() {
    guard observer == nil else { return }
    observer = DistributedNotificationCenter.default().addObserver(
      forName: Self.accessibilityChanged, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.systemSettingsChanged() }
    }
  }

  func stop() {
    if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    observer = nil
    pendingRead?.cancel()
    pendingRead = nil
  }

  /// Reads the state now and reports a change.
  @discardableResult
  func refresh() -> PermissionStatus {
    let old = status
    status = checker.status()
    if status != old {
      Log.ui.info(
        "permissions: accessibility \(self.status.accessibility, privacy: .public), postEvent \(self.status.postEvent, privacy: .public)"
      )
      onChange(status, status.newlyGranted(since: old))
    }
    return status
  }

  /// Schedules a read after the delay; a later notification restarts the wait.
  func systemSettingsChanged() {
    pendingRead?.cancel()
    pendingRead = Task { [weak self, delay] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      self?.refresh()
    }
  }

  /// Waits for the scheduled read, for tests.
  func settle() async {
    await pendingRead?.value
  }
}
