// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import SwiftUI
import Testing

@testable import DictApp

private let renderDirectory = ProcessInfo.processInfo.environment["DICT_ONBOARDING_RENDER_DIR"]

/// `TEST_RUNNER_DICT_ONBOARDING_RENDER_DIR=<dir> xcodebuild test …` writes one PNG per step and
/// state into `<dir>`, offscreen; add `-testLanguage zh-Hans` for the Chinese UI.
@MainActor
struct OnboardingRenderTests {
  @Test func everyStepLaysOut() async {
    for (_, model) in await Self.samples() {
      let view = NSHostingView(rootView: OnboardingView(model: model, appName: "Dict"))
      view.layoutSubtreeIfNeeded()
      #expect(view.fittingSize.width == OnboardingView.width)
      #expect(view.fittingSize.height > 200)
    }
  }

  @Test(.enabled(if: renderDirectory != nil))
  func renderSteps() async throws {
    let directory = URL(fileURLWithPath: try #require(renderDirectory))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (name, model) in await Self.samples() {
      for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        // Offscreen, the window background must be drawn by the view itself.
        let view = NSHostingView(
          rootView: OnboardingView(model: model, appName: "Dict")
            .background(Color(nsColor: .windowBackgroundColor)))
        view.appearance = NSAppearance(named: appearance)
        view.frame.size = view.fittingSize
        let window = NSWindow(
          contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = view.appearance
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(scheme)-\(name).png"))
      }
    }
  }

  private static func samples() async -> [(String, OnboardingModel)] {
    func model(
      _ step: OnboardingStep, accessibility: Bool = false,
      languages: AppleTranslationAvailability = .installed
    ) async -> OnboardingModel {
      let defaults = UserDefaults(suiteName: "OnboardingRenderTests") ?? .standard
      let model = OnboardingModel(
        hotkeys: HotkeyCenter(defaults: defaults),
        permissions: PermissionStatus(accessibility: accessibility, postEvent: accessibility),
        defaults: defaults, languageStatus: { _, _ in languages })
      model.step = step
      await model.refreshLanguages(LanguagePair())
      return model
    }
    return [
      ("accessibility-off", await model(.accessibility)),
      ("accessibility-on", await model(.accessibility, accessibility: true)),
      ("shortcuts", await model(.shortcuts)),
      ("translation-ready", await model(.translation)),
      ("translation-download", await model(.translation, languages: .needsDownload)),
      ("translation-unsupported", await model(.translation, languages: .unsupported)),
    ]
  }
}
