// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import Foundation
import Testing

@testable import DictApp

private let renderDirectory = ProcessInfo.processInfo.environment["DICT_MAINWINDOW_RENDER_DIR"]

/// The real main window over the gallery's sample data, built but never ordered on screen.
///
/// `TEST_RUNNER_DICT_MAINWINDOW_RENDER_DIR=<dir> xcodebuild test … -only-testing:
/// DictAppTests/MainWindowGalleryTests` writes one PNG per page, state and appearance into
/// `<dir>` at 1280×800; add `-testLanguage zh-Hans` for the Chinese UI.
@MainActor
struct MainWindowGalleryTests {
  /// A window over `data` with settings that never touch the user's defaults or keychain.
  static func makeController(data: WindowData) throws -> MainWindowController {
    MainWindowGallery.makeController(data: data)
  }

  @Test func everyPageLaysOutAtTheMinimumSize() async throws {
    let controller = try Self.makeController(data: try await MainWindowGallery.sampleData())
    let window = try #require(controller.window)
    window.setContentSize(WindowLayout.minimumSize)
    for section in MainSection.allCases {
      controller.context.navigation.section = section
      window.contentView?.layoutSubtreeIfNeeded()
      #expect(window.contentView?.fittingSize.width ?? 0 <= WindowLayout.minimumSize.width)
    }
    #expect(!window.isVisible)
  }

  @Test func everyDemoStateOpensOnItsPage() async throws {
    for state in MainWindowDemo.State.allCases {
      let controller = try await MainWindowDemo.makeController(state, width: 960)
      let window = try #require(controller.window)
      #expect(window.contentLayoutRect.width == 960)
      #expect(!window.isVisible)
      switch state {
      case .historyCorrection:
        if case .sentence(let event) = controller.context.data.history.selected {
          #expect(event.kind == .corrected)
        } else {
          Issue.record("no correction selected")
        }
      case .reviewRevealed:
        #expect(controller.context.navigation.section == .review)
      case .settingsModel:
        #expect(controller.context.navigation.section == .settings)
      default:
        #expect(controller.context.navigation.section.rawValue == state.rawValue)
      }
    }
  }

  @Test(.enabled(if: renderDirectory != nil))
  func renderWindow() async throws {
    let directory = URL(fileURLWithPath: try #require(renderDirectory))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let language = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? "zh" : "en"
    let sample = try await MainWindowGallery.sampleData()
    let states: [(String, WindowData, (MainNavigation) -> Void)] = [
      ("today", sample, { $0.section = .today }),
      ("today-empty", try await MainWindowGallery.emptyData(), { $0.section = .today }),
      ("settings", sample, { $0.section = .settings }),
      ("settings-model", sample, { $0.show(.model) }),
      ("settings-privacy", sample, { $0.show(.privacy) }),
      ("history", try await Self.historyData { _ in }, { $0.section = .history }),
      (
        "history-sentence", try await Self.historyData { $0.selectedID = Self.firstCorrection($0) },
        { $0.section = .history }
      ),
      (
        "history-search", try await Self.historyData { await $0.setSearch("run") },
        { $0.section = .history }
      ),
      (
        "history-filtered", try await Self.historyData { await $0.setKind(.translations) },
        { $0.section = .history }
      ),
      (
        "history-empty", try await Self.historyData(empty: true) { _ in }, { $0.section = .history }
      ),
      ("saved", sample, { $0.section = .saved }),
      ("saved-empty", try await MainWindowGallery.emptyData(), { $0.section = .saved }),
    ]
    let reviewStates = try await ReviewGalleryTests.states()
    for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
      for (name, data, navigate) in states + reviewStates {
        let controller = try Self.makeController(data: data)
        let window = try #require(controller.window)
        window.appearance = NSAppearance(named: appearance)
        window.setContentSize(WindowLayout.defaultSize)
        navigate(controller.context.navigation)
        let png = try #require(Self.render(window))
        try png.write(to: directory.appendingPathComponent("\(language)-\(scheme)-\(name).png"))
        // The History page also at the smallest width, where its columns are tightest.
        if name.hasPrefix("history") {
          window.setContentSize(WindowLayout.minimumSize)
          let narrow = try #require(Self.render(window))
          try narrow.write(
            to: directory.appendingPathComponent("\(language)-\(scheme)-\(name)-narrow.png"))
        }
      }
      // The model section at the narrowest width, where its rows must shrink or stack.
      let controller = try Self.makeController(data: sample)
      let window = try #require(controller.window)
      window.appearance = NSAppearance(named: appearance)
      window.setContentSize(WindowLayout.minimumSize)
      controller.context.navigation.show(.model)
      let png = try #require(Self.render(window))
      try png.write(
        to: directory.appendingPathComponent("\(language)-\(scheme)-settings-model-narrow.png"))
    }
  }

  /// The sample data with the History page's state prepared by `prepare`.
  static func historyData(empty: Bool = false, _ prepare: (HistoryModel) async -> Void)
    async throws -> WindowData
  {
    let data =
      try await empty ? MainWindowGallery.emptyData() : MainWindowGallery.sampleData()
    await data.history.reload()
    await prepare(data.history)
    return data
  }

  /// The first correction in the loaded history.
  static func firstCorrection(_ history: HistoryModel) -> String? {
    history.items.first {
      if case .sentence(let event) = $0 { event.kind == .corrected } else { false }
    }?.historyID
  }

  /// The window's frame view, title bar and traffic lights included.
  static func render(_ window: NSWindow) -> Data? {
    guard let frame = window.contentView?.superview else { return nil }
    frame.layoutSubtreeIfNeeded()
    // SwiftUI applies a state change on the next turn of the run loop.
    RunLoop.main.run(until: .now.addingTimeInterval(0.2))
    frame.layoutSubtreeIfNeeded()
    guard let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return nil }
    frame.cacheDisplay(in: frame.bounds, to: bitmap)
    return bitmap.representation(using: .png, properties: [:])
  }
}
