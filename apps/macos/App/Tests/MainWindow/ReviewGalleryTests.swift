// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import Foundation
import Testing

@testable import DictApp

/// The review page's states for the window gallery (`MainWindowGalleryTests.renderWindow()`
/// renders them at the default and the minimum width).
@MainActor
struct ReviewGalleryTests {
  /// Each state over a store of its own, as rating writes to it.
  static func states() async throws -> [(String, WindowData, (MainNavigation) -> Void)] {
    let show: (MainNavigation) -> Void = { $0.section = .review }
    // 3 / 9 as in the mockup: one forgotten, two remembered, 「candid」 next.
    let front = try await reviewing(answers: [.again, .good, .good])
    let revealed = try await reviewing(answers: [.again, .good, .good])
    revealed.review.reveal()
    // The first word has no sentence and asks with itself.
    let word = try await reviewing(answers: [])
    word.review.reveal()
    let done = try await reviewing(answers: [.again] + Array(repeating: .good, count: 9))
    let stopped = try await reviewing(answers: [.good, .again])
    await stopped.review.end()
    let empty = try await MainWindowGallery.emptyData()
    await empty.review.appear()
    return [
      ("review", front, show), ("review-revealed", revealed, show), ("review-word", word, show),
      ("review-done", done, show), ("review-stopped", stopped, show),
      ("review-empty", empty, show),
    ]
  }

  private static func reviewing(answers: [Rating]) async throws -> WindowData {
    try await MainWindowGallery.reviewingData(answers: answers)
  }
}
