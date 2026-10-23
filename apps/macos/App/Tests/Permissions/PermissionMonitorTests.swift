// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Synchronization
import Testing

@testable import DictApp

/// A checker whose answer the test sets.
private final class FakeChecker: PermissionChecker {
  private let current: Mutex<PermissionStatus>

  init(_ status: PermissionStatus) { current = Mutex(status) }

  func set(_ status: PermissionStatus) { current.withLock { $0 = status } }
  func status() -> PermissionStatus { current.withLock { $0 } }
}

@MainActor
struct PermissionMonitorTests {
  private let none = PermissionStatus(accessibility: false, postEvent: false)
  private let granted = PermissionStatus(accessibility: true, postEvent: true)

  @Test func readsTheStateWhenCreated() {
    let monitor = PermissionMonitor(checker: FakeChecker(granted))
    #expect(monitor.status == granted)
  }

  @Test func refreshReportsOnlyChanges() {
    let checker = FakeChecker(none)
    let monitor = PermissionMonitor(checker: checker)
    var changes: [(PermissionStatus, Set<Permission>)] = []
    monitor.onChange = { changes.append(($0, $1)) }

    monitor.refresh()
    #expect(changes.isEmpty)

    checker.set(PermissionStatus(accessibility: true, postEvent: false))
    #expect(monitor.refresh().accessibility)
    checker.set(granted)
    monitor.refresh()
    checker.set(none)
    monitor.refresh()

    #expect(changes.map(\.1) == [[.accessibility], [.postEvent], []])
    #expect(
      changes.map(\.0) == [PermissionStatus(accessibility: true, postEvent: false), granted, none])
  }

  /// A grant made in System Settings is picked up after the notification and the delay,
  /// without a restart.
  @Test func notificationReadsAgainAfterTheDelay() async {
    let checker = FakeChecker(none)
    let monitor = PermissionMonitor(checker: checker, delay: .milliseconds(30))
    var granted: [Set<Permission>] = []
    monitor.onChange = { granted.append($1) }

    monitor.systemSettingsChanged()
    // The notification arrives before the system has updated the answer.
    checker.set(PermissionStatus(accessibility: true, postEvent: false))
    #expect(monitor.status == none)
    await monitor.settle()

    #expect(monitor.status.accessibility)
    #expect(granted == [[.accessibility]])
  }

  @Test func laterNotificationRestartsTheWait() async {
    let checker = FakeChecker(none)
    let monitor = PermissionMonitor(checker: checker, delay: .milliseconds(30))
    var reads = 0
    monitor.onChange = { _, _ in reads += 1 }

    monitor.systemSettingsChanged()
    monitor.systemSettingsChanged()
    checker.set(granted)
    await monitor.settle()

    #expect(reads == 1)
  }

  @Test func stopCancelsAPendingRead() async throws {
    let checker = FakeChecker(none)
    let monitor = PermissionMonitor(checker: checker, delay: .milliseconds(30))
    monitor.start()
    monitor.systemSettingsChanged()
    checker.set(granted)
    monitor.stop()
    try await Task.sleep(for: .milliseconds(80))
    #expect(monitor.status == none)
  }
}
