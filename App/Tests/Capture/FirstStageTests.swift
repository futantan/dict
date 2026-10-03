// SPDX-License-Identifier: GPL-3.0-or-later

import ApplicationServices
import Testing

@testable import DictApp

/// A clock that only moves when the poll loop sleeps or an attempt takes time.
final class FakeClock {
  var now: Duration = .zero
}

struct FirstStageTests {
  func poll(
    _ attempts: [ReadAttempt<String>], attemptCost: Duration = .milliseconds(1),
    clock: FakeClock = FakeClock()
  ) -> (FirstStageOutcome<String>, calls: Int) {
    var remaining = attempts
    var calls = 0
    let outcome = pollFirstStage(
      deadline: .milliseconds(150), interval: .milliseconds(10),
      elapsed: { clock.now }, sleep: { clock.now += $0 },
      attempt: {
        calls += 1
        clock.now += attemptCost
        return remaining.count > 1 ? remaining.removeFirst() : remaining[0]
      })
    return (outcome, calls)
  }

  @Test func returnsTheFirstFoundSelection() {
    let (outcome, calls) = poll([.found("Hello")])
    #expect(outcome == .found("Hello"))
    #expect(calls == 1)
  }

  @Test func retriesNoValueUntilReadable() {
    let (outcome, calls) = poll([.notReady(.noValue), .notReady(.noValue), .found("Hello")])
    #expect(outcome == .found("Hello"))
    #expect(calls == 3)
  }

  @Test func givesUpAtTheDeadlineWithTheLastError() {
    let clock = FakeClock()
    let (outcome, calls) = poll([.notReady(.noValue)], clock: clock)
    #expect(outcome == .failed(.unreadable(axError: AXError.noValue.rawValue)))
    #expect(clock.now <= .milliseconds(150))
    // 1 ms per attempt plus 10 ms per sleep: 14 attempts fit in 150 ms.
    #expect(calls == 14)
  }

  @Test func neverStartsAnAttemptThatCannotFinishBeforeTheDeadline() {
    let clock = FakeClock()
    let (_, calls) = poll([.notReady(.noValue)], attemptCost: .milliseconds(100), clock: clock)
    #expect(calls == 1)
  }

  @Test func secureFieldStopsImmediately() {
    let (outcome, calls) = poll([.secureField, .found("never")])
    #expect(outcome == .failed(.secureField))
    #expect(calls == 1)
  }

  @Test func emptySelectionReportsTheFieldText() {
    let (outcome, _) = poll([.empty(fieldText: "line one\nline two")])
    #expect(outcome == .failed(.nothingSelected(fieldText: "line one\nline two")))
  }

  @Test func apiDisabledMeansPermissionLost() {
    let (outcome, _) = poll([.failed(.apiDisabled)])
    #expect(outcome == .failed(.noAccessibilityPermission))
  }

  @Test func otherErrorsAreUnreadableWithTheCode() {
    let (outcome, calls) = poll([.failed(.attributeUnsupported), .found("never")])
    #expect(outcome == .failed(.unreadable(axError: AXError.attributeUnsupported.rawValue)))
    #expect(calls == 1)
  }
}
