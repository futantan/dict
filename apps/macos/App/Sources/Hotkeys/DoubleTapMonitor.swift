// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Watches modifier keys in every app and reports double presses (architecture 10.1).
///
/// Unlike a Carbon hotkey, nothing is consumed: the frontmost app sees the presses too.
/// The global monitor sees other apps' key events only with the Accessibility permission;
/// the local one covers this app's own windows, where the global one sees nothing.
@MainActor
final class DoubleTapMonitor {
  private var detector: DoubleTapDetector
  private var monitors: [Any] = []
  private let onDoubleTap: @MainActor (ModifierKey) -> Void

  private static let events: NSEvent.EventTypeMask = [
    .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
  ]

  init(
    window: TimeInterval = DoubleTapDetector.defaultWindow,
    onDoubleTap: @escaping @MainActor (ModifierKey) -> Void
  ) {
    detector = DoubleTapDetector(window: window)
    self.onDoubleTap = onDoubleTap
  }

  var isRunning: Bool { !monitors.isEmpty }

  func start() {
    guard monitors.isEmpty else { return }
    let global = NSEvent.addGlobalMonitorForEvents(matching: Self.events) { [weak self] event in
      let (input, time) = Self.input(for: event)
      MainActor.assumeIsolated { self?.handle(input, at: time) }
    }
    let local = NSEvent.addLocalMonitorForEvents(matching: Self.events) { [weak self] event in
      let (input, time) = Self.input(for: event)
      MainActor.assumeIsolated { self?.handle(input, at: time) }
      return event
    }
    monitors = [global, local].compactMap { $0 }
  }

  /// Safe to call more than once.
  func stop() {
    monitors.forEach(NSEvent.removeMonitor)
    monitors = []
    detector = DoubleTapDetector(window: detector.window)
  }

  private func handle(_ input: DoubleTapDetector.Input, at time: TimeInterval) {
    if let key = detector.handle(input, at: time) { onDoubleTap(key) }
  }

  nonisolated static func input(for event: NSEvent) -> (DoubleTapDetector.Input, TimeInterval) {
    let input: DoubleTapDetector.Input =
      event.type == .flagsChanged
      ? .modifiers(ModifierKey.held(in: event.modifierFlags, changed: event.keyCode))
      : .otherInput
    return (input, event.timestamp)
  }
}
