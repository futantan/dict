// SPDX-License-Identifier: GPL-3.0-or-later

import Synchronization

/// How long a model call may stay silent (architecture 6.4). Thinking deltas count as events.
public struct ModelTimeouts: Sendable, Equatable {
  public var firstEvent: Duration
  public var idle: Duration
  public var total: Duration

  public init(firstEvent: Duration, idle: Duration, total: Duration) {
    self.firstEvent = firstEvent
    self.idle = idle
    self.total = total
  }

  public static let standard = ModelTimeouts(
    firstEvent: .seconds(10), idle: .seconds(15), total: .seconds(120))
}

/// Tracks the time since the last event and reports which timeout expires first.
protocol ModelWatchdog: Sendable {
  /// Records that an event arrived.
  func feed()
  /// Returns when a timeout expires; throws `CancellationError` when cancelled first.
  func expiry() async throws -> TimeoutStage
}

final class Watchdog<C: Clock<Duration>>: ModelWatchdog {
  private let clock: C
  private let timeouts: ModelTimeouts
  private let start: C.Instant
  private let lastEvent = Mutex<C.Instant?>(nil)

  init(clock: C, timeouts: ModelTimeouts) {
    self.clock = clock
    self.timeouts = timeouts
    self.start = clock.now
  }

  func feed() {
    let now = clock.now
    lastEvent.withLock { $0 = now }
  }

  func expiry() async throws -> TimeoutStage {
    let totalDeadline = start.advanced(by: timeouts.total)
    while true {
      let last = lastEvent.withLock { $0 }
      let stage: TimeoutStage = last == nil ? .firstEvent : .idle
      let deadline =
        last.map { $0.advanced(by: timeouts.idle) } ?? start.advanced(by: timeouts.firstEvent)
      if totalDeadline <= deadline {
        try await clock.sleep(until: totalDeadline, tolerance: nil)
        return .total
      }
      try await clock.sleep(until: deadline, tolerance: nil)
      if lastEvent.withLock({ $0 }) == last { return stage }
    }
  }
}
