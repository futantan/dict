// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Testing

@testable import DictApp

/// Feeds the detector modifier snapshots and other input at chosen times (seconds).
struct DoubleTapDetectorTests {
  private typealias Step = (input: DoubleTapDetector.Input, at: Double)

  /// Every key that fired, in order.
  private func run(_ steps: [Step], window: Double = 0.3) -> [ModifierKey] {
    var detector = DoubleTapDetector(window: window)
    return steps.compactMap { detector.handle($0.input, at: $0.at) }
  }

  private func held(_ keys: ModifierKey...) -> DoubleTapDetector.Input { .modifiers(Set(keys)) }
  private let none = DoubleTapDetector.Input.modifiers([])

  /// Press and release `key` at `start`, `start + 0.05`.
  private func tap(_ key: ModifierKey, at start: Double) -> [Step] {
    [(held(key), start), (none, start + 0.05)]
  }

  @Test func twoQuickTapsOfTheSameKeyFireOnTheSecondRelease() {
    var detector = DoubleTapDetector()
    #expect(detector.handle(held(.leftOption), at: 0) == nil)
    #expect(detector.handle(none, at: 0.05) == nil)
    #expect(detector.handle(held(.leftOption), at: 0.15) == nil)
    #expect(detector.handle(none, at: 0.2) == .leftOption)
  }

  @Test func theDefaultWindowIs300Milliseconds() {
    #expect(DoubleTapDetector().window == 0.3)
  }

  @Test(arguments: [(0.34, true), (0.4, false)])
  func theGapBetweenTapsMustFitTheWindow(secondStart: Double, fires: Bool) {
    // First release at 0.05, so the gaps are 0.29 s and 0.35 s.
    let fired = run(tap(.leftCommand, at: 0) + tap(.leftCommand, at: secondStart))
    #expect(fired == (fires ? [.leftCommand] : []))
  }

  @Test func theWindowCanBeChanged() {
    let steps = tap(.leftOption, at: 0) + tap(.leftOption, at: 0.45)
    #expect(run(steps) == [])
    #expect(run(steps, window: 0.5) == [.leftOption])
  }

  @Test func twoDifferentKeysDoNotFire() {
    #expect(run(tap(.leftOption, at: 0) + tap(.leftControl, at: 0.1)) == [])
  }

  @Test func leftAndRightAreDifferentKeys() {
    #expect(run(tap(.leftCommand, at: 0) + tap(.rightCommand, at: 0.1)) == [])
    #expect(run(tap(.rightCommand, at: 0) + tap(.rightCommand, at: 0.1)) == [.rightCommand])
  }

  @Test func anotherKeyBetweenTheTapsCancels() {
    let steps = tap(.leftOption, at: 0) + [(.otherInput, 0.08)] + tap(.leftOption, at: 0.1)
    #expect(run(steps) == [])
  }

  @Test func aKeyPressedWithTheModifierCancels() {
    // ⌘C, then a quick ⌘ tap: the first press was a combination, not a tap.
    let steps: [Step] =
      [(held(.leftCommand), 0), (.otherInput, 0.03), (none, 0.06)] + tap(.leftCommand, at: 0.1)
    #expect(run(steps) == [])
  }

  @Test func aKeyPressedDuringTheSecondPressCancels() {
    // ⌥ tap, then ⌥D: the second press is a combination.
    let steps: [Step] =
      tap(.leftOption, at: 0) + [(held(.leftOption), 0.1), (.otherInput, 0.12), (none, 0.15)]
    #expect(run(steps) == [])
  }

  @Test func anotherModifierHeldAtTheSameTimeCancels() {
    let steps: [Step] =
      tap(.leftOption, at: 0) + [
        (held(.leftOption), 0.1), (held(.leftOption, .leftShift), 0.12), (held(.leftOption), 0.14),
        (none, 0.16),
      ]
    #expect(run(steps) == [])
    let firstWithShift: [Step] =
      [(held(.leftShift), 0), (held(.leftShift, .leftOption), 0.02), (held(.leftOption), 0.04)]
      + [(none, 0.06)] + tap(.leftOption, at: 0.1)
    #expect(run(firstWithShift) == [])
  }

  @Test func holdingTheKeyDoesNotFire() {
    // A long first press, then a quick tap.
    #expect(run([(held(.leftOption), 0), (none, 0.5)] + tap(.leftOption, at: 0.55)) == [])
    // A quick tap, then a long second press.
    #expect(run(tap(.leftOption, at: 0) + [(held(.leftOption), 0.1), (none, 0.9)]) == [])
    // Held and never released.
    #expect(run(tap(.leftOption, at: 0) + [(held(.leftOption), 0.1)]) == [])
  }

  @Test func aTripleTapFiresOnce() {
    let steps = tap(.leftOption, at: 0) + tap(.leftOption, at: 0.1) + tap(.leftOption, at: 0.2)
    #expect(run(steps) == [.leftOption])
  }

  @Test func aFourthTapFiresAgain() {
    let steps =
      tap(.leftOption, at: 0) + tap(.leftOption, at: 0.1) + tap(.leftOption, at: 0.2)
      + tap(.leftOption, at: 0.3)
    #expect(run(steps) == [.leftOption, .leftOption])
  }

  @Test func repeatedSnapshotsChangeNothing() {
    // flagsChanged also arrives for Caps Lock and fn, with the same modifiers held.
    let steps: [Step] =
      [(held(.leftOption), 0), (held(.leftOption), 0.02), (none, 0.05), (none, 0.07)]
      + tap(.leftOption, at: 0.1)
    #expect(run(steps) == [.leftOption])
  }

  @Test func aStaleHoldIsForgottenOnceReleased() {
    // ⌘ held for seconds, as when the monitor starts mid-press, then released.
    let steps: [Step] =
      [(held(.leftCommand), 0), (none, 5)] + tap(.leftOption, at: 6) + tap(.leftOption, at: 6.1)
    #expect(run(steps) == [.leftOption])
  }
}

struct ModifierKeyTests {
  @Test func heldKeysComeFromTheLeftAndRightBits() {
    // ⌘ with the right-command bit (0x10) and ⌥ with the left-option bit (0x20).
    let flags = NSEventFlags.make([.command, .option], deviceBits: 0x10 | 0x20)
    #expect(ModifierKey.held(in: flags, changed: 0) == [.rightCommand, .leftOption])
  }

  @Test func withoutSideBitsTheChangedKeyDecides() {
    let flags = NSEventFlags.make([.command], deviceBits: 0)
    #expect(
      ModifierKey.held(in: flags, changed: ModifierKey.rightCommand.keyCode) == [.rightCommand])
    #expect(ModifierKey.held(in: flags, changed: ModifierKey.leftOption.keyCode) == [.leftCommand])
  }

  @Test func keyCodesRoundTrip() {
    for key in ModifierKey.allCases {
      #expect(ModifierKey(keyCode: key.keyCode) == key)
    }
    #expect(ModifierKey(keyCode: 0) == nil)
  }
}

private enum NSEventFlags {
  static func make(_ flags: NSEvent.ModifierFlags, deviceBits: UInt) -> NSEvent.ModifierFlags {
    NSEvent.ModifierFlags(rawValue: flags.rawValue | deviceBits)
  }
}
