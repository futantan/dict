// SPDX-License-Identifier: GPL-3.0-or-later

/// Lets streamed text into the panel at most once per display frame. A model sends a chunk
/// every few milliseconds (measured: 14 chunks in 40 ms for one sentence), and each update
/// re-renders the whole text, so the panel takes the latest text once a frame instead.
///
/// The first chunk after a quiet frame shows at once; later ones within the frame are held
/// and the latest is shown when the frame ends. Any state that is not streaming text, such
/// as the finished result, shows at once and drops what was held. Each state carries the
/// whole text so far, so dropping intermediate ones loses nothing.
@MainActor
final class StreamThrottle {
  private let interval: Duration
  private let deliver: (PanelState) -> Void
  private let clock = ContinuousClock()
  private var lastDelivery: ContinuousClock.Instant?
  private var held: PanelState?
  private var flush: Task<Void, Never>?

  init(interval: Duration, deliver: @escaping (PanelState) -> Void) {
    self.interval = interval
    self.deliver = deliver
  }

  func submit(_ state: PanelState) {
    guard case .generating = state.phase else {
      cancel()
      send(state)
      return
    }
    guard let last = lastDelivery, clock.now < last.advanced(by: interval) else {
      send(state)
      return
    }
    held = state
    guard flush == nil else { return }
    let due = last.advanced(by: interval)
    flush = Task { [weak self, clock] in
      try? await Task.sleep(until: due, clock: clock)
      guard !Task.isCancelled, let self else { return }
      self.flush = nil
      if let held = self.held { self.send(held) }
    }
  }

  /// Drops held text, for example when the panel hides or shows a new session.
  func cancel() {
    flush?.cancel()
    flush = nil
    held = nil
    lastDelivery = nil
  }

  private func send(_ state: PanelState) {
    held = nil
    lastDelivery = clock.now
    deliver(state)
  }
}
