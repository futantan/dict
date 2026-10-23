// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import DictApp

struct ToastLifetimeTests {
  private let t0 = ContinuousClock.now

  private func at(_ seconds: Double) -> ContinuousClock.Instant {
    t0 + .milliseconds(Int(seconds * 1000))
  }

  @Test func itHidesThreeSecondsAfterShowing() {
    let lifetime = ToastLifetime(shownAt: t0)
    #expect(!lifetime.shouldHide(at: at(2.9)))
    #expect(lifetime.shouldHide(at: at(3)))
  }

  /// The pointer was over the previous toast and AppKit never reported it leaving (the panel
  /// was hidden or moved under a still pointer), so the next toast must not inherit it.
  @Test func hoverLeftOverFromThePreviousToastDoesNotKeepTheNextOneUp() {
    var lifetime = ToastLifetime(shownAt: t0)
    lifetime.setHovering(true, at: at(1))
    lifetime.show(at: at(2))
    #expect(!lifetime.shouldHide(at: at(4.9)))
    #expect(lifetime.shouldHide(at: at(5)))
  }

  /// The toast appeared under a resting pointer: it entered and never left.
  @Test func aPointerRestingOnTheToastHidesItAfterTheCap() {
    var lifetime = ToastLifetime(shownAt: t0)
    lifetime.setHovering(true, at: at(0.1))
    #expect(!lifetime.shouldHide(at: at(10)))
    #expect(lifetime.shouldHide(at: at(0.1) + ToastLifetime.hoverCap))
    #expect(lifetime.shouldHide(at: at(120)))
  }

  @Test func itHidesThreeSecondsAfterThePointerLeaves() {
    var lifetime = ToastLifetime(shownAt: t0)
    lifetime.setHovering(true, at: at(1))
    lifetime.setHovering(false, at: at(6))
    #expect(!lifetime.shouldHide(at: at(8.9)))
    #expect(lifetime.shouldHide(at: at(9)))
  }

  @Test func aBriefHoverOnlyExtendsIt() {
    var lifetime = ToastLifetime(shownAt: t0)
    lifetime.setHovering(true, at: at(0.2))
    lifetime.setHovering(false, at: at(0.5))
    #expect(!lifetime.shouldHide(at: at(3.4)))
    #expect(lifetime.shouldHide(at: at(3.5)))
  }

  /// The cap counts from when the pointer entered, not from each repeated report of it.
  @Test func repeatedEnterReportsDoNotRestartTheCap() {
    var lifetime = ToastLifetime(shownAt: t0)
    lifetime.setHovering(true, at: at(1))
    lifetime.setHovering(true, at: at(10))
    #expect(lifetime.shouldHide(at: at(16)))
  }
}
