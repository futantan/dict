// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import Foundation
import Testing

@testable import DictApp

private let renderDirectory = ProcessInfo.processInfo.environment["DICT_MAINWINDOW_RENDER_DIR"]

/// The review page's states for the window gallery (`MainWindowGalleryTests.renderWindow()`
/// renders them at the default size); this renders them again at the minimum width, where
/// the summary goes under the card.
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
    let data = try await MainWindowGallery.sampleData()
    await data.review.appear()
    for rating in answers {
      data.review.reveal()
      await data.review.answer(rating)
    }
    return data
  }

  @Test(.enabled(if: renderDirectory != nil))
  func renderReviewAtTheMinimumWidth() async throws {
    let directory = URL(fileURLWithPath: try #require(renderDirectory))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let language = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? "zh" : "en"
    let size = CGSize(
      width: WindowLayout.minimumSize.width, height: WindowLayout.defaultSize.height)
    for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
      for (name, data, navigate) in try await Self.states() {
        let controller = try MainWindowGalleryTests.makeController(data: data)
        let window = try #require(controller.window)
        window.appearance = NSAppearance(named: appearance)
        window.setContentSize(size)
        navigate(controller.context.navigation)
        let png = try #require(MainWindowGalleryTests.render(window))
        try png.write(
          to: directory.appendingPathComponent("\(language)-\(scheme)-\(name)-960.png"))
      }
    }
  }
}
