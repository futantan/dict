// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Recognizes a modifier key pressed twice on its own, as a pure state machine over
/// modifier snapshots and other input, with times passed in (architecture 10.1).
///
/// A double press is two taps of the same physical key with nothing else in between: each
/// press lasts at most `window`, and the second starts at most `window` after the first
/// ends. It fires on the second release, so a quick ⌥ tap followed by ⌥D does not fire.
/// Any other key or click, or a second modifier held at the same time, cancels; after a
/// double press the count starts over, so a triple press fires once.
struct DoubleTapDetector: Sendable {
  enum Input: Equatable, Sendable {
    /// The modifier keys held now, after a `flagsChanged` event.
    case modifiers(Set<ModifierKey>)
    /// A key or mouse button went down.
    case otherInput
  }

  /// Long enough for a relaxed double press, short enough that two separate uses of a
  /// modifier, such as two ⌘-clicks, do not join up.
  static let defaultWindow: TimeInterval = 0.3

  let window: TimeInterval
  private var held: Set<ModifierKey> = []
  private var phase = Phase.idle

  private enum Phase: Equatable {
    case idle
    case firstDown(ModifierKey, at: TimeInterval)
    case firstUp(ModifierKey, at: TimeInterval)
    case secondDown(ModifierKey, at: TimeInterval)
    /// Something else happened while keys were held; wait for all of them to be released.
    case spoiled
  }

  init(window: TimeInterval = defaultWindow) {
    self.window = window
  }

  /// Returns the key that has just been pressed twice, if any.
  mutating func handle(_ input: Input, at time: TimeInterval) -> ModifierKey? {
    switch input {
    case .otherInput:
      phase = held.isEmpty ? .idle : .spoiled
      return nil
    case .modifiers(let now):
      let previous = held
      held = now
      guard now != previous else { return nil }
      if now.isEmpty {
        return released(at: time)
      }
      guard now.count == 1, previous.isEmpty, let key = now.first else {
        phase = .spoiled
        return nil
      }
      pressed(key, at: time)
      return nil
    }
  }

  private mutating func pressed(_ key: ModifierKey, at time: TimeInterval) {
    if case .firstUp(key, let upAt) = phase, time - upAt <= window {
      phase = .secondDown(key, at: time)
    } else {
      phase = .firstDown(key, at: time)
    }
  }

  private mutating func released(at time: TimeInterval) -> ModifierKey? {
    switch phase {
    case .firstDown(let key, let downAt) where time - downAt <= window:
      phase = .firstUp(key, at: time)
      return nil
    case .secondDown(let key, let downAt) where time - downAt <= window:
      phase = .idle
      return key
    default:
      phase = .idle
      return nil
    }
  }
}
