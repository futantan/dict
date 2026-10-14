// SPDX-License-Identifier: GPL-3.0-or-later

/// When the toast hides: `linger` after it shows or after the pointer last left it, and at
/// most `hoverCap` into a hover. Hovering only ever extends it, never indefinitely: AppKit
/// may never report the pointer leaving (the toast appeared under a resting pointer, or was
/// hidden or moved while hovered), so a hover is trusted for a bounded time and every new
/// message starts unhovered.
struct ToastLifetime: Equatable, Sendable {
  typealias Instant = ContinuousClock.Instant

  static let linger = Duration.seconds(3)
  static let hoverCap = Duration.seconds(15)

  private(set) var shownAt: Instant
  /// When the current hover began; nil when the pointer is not over the toast.
  private(set) var hoverStartedAt: Instant?
  private(set) var lastLeftAt: Instant?

  init(shownAt: Instant) {
    self.shownAt = shownAt
  }

  /// A new message on screen; any hover from the previous one is forgotten.
  mutating func show(at now: Instant) {
    self = ToastLifetime(shownAt: now)
  }

  /// The pointer entered or left the toast.
  mutating func setHovering(_ hovering: Bool, at now: Instant) {
    if hovering {
      if hoverStartedAt == nil { hoverStartedAt = now }
    } else if hoverStartedAt != nil {
      hoverStartedAt = nil
      lastLeftAt = now
    }
  }

  func shouldHide(at now: Instant) -> Bool {
    now >= hideAt
  }

  private var hideAt: Instant {
    let afterShowing = max(shownAt, lastLeftAt ?? shownAt) + Self.linger
    guard let hoverStartedAt else { return afterShowing }
    return max(afterShowing, hoverStartedAt + Self.hoverCap)
  }
}
