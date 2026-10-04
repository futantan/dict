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
  @Test func everyStepLaysOut() {
    for (_, model) in Self.samples() {
      let view = NSHostingView(rootView: OnboardingView(model: model, appName: "Dict"))
      view.layoutSubtreeIfNeeded()
      #expect(view.fittingSize.width == OnboardingView.width)
      #expect(view.fittingSize.height > 200)
    }
  }

  @Test(.enabled(if: renderDirectory != nil))
  func renderSteps() throws {
    let directory = URL(fileURLWithPath: try #require(renderDirectory))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let language = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? "zh" : "en"
    for (name, model) in Self.samples() {
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
        try png.write(
          to: directory.appendingPathComponent("onboarding-\(language)-\(scheme)-\(name).png"))
      }
    }
  }

  private static func samples() -> [(String, OnboardingModel)] {
    func model(
      _ step: OnboardingStep, accessibility: Bool = false, read: Bool = false,
      provider: String? = nil, key: String? = nil, connection: ConnectionStatus = .idle
    ) -> OnboardingModel {
      let suite = "OnboardingRenderTests.\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: suite) ?? .standard
      defaults.removePersistentDomain(forName: suite)
      if read {
        HotkeyStore(defaults: defaults).save([
          .read: KeyCombo(keyCode: 2, modifiers: [.control, .option])
        ])
      }
      PreferencesStore(defaults: defaults).save(
        Preferences(model: ModelPreferences(providerID: provider)))
      let secrets = InMemorySecretStore(provider.flatMap { id in key.map { [id: $0] } } ?? [:])
      let settings = SettingsModel(defaults: defaults, secrets: secrets)
      settings.showConnection(connection)
      let model = OnboardingModel(
        hotkeys: HotkeyCenter(defaults: defaults), settings: settings,
        permissions: PermissionStatus(accessibility: accessibility, postEvent: accessibility),
        defaults: defaults)
      model.step = step
      return model
    }
    let key = "sk-render-sample-0000000000000000"
    return [
      ("1-accessibility-off", model(.accessibility)),
      ("1-accessibility-on", model(.accessibility, accessibility: true)),
      ("2-shortcuts", model(.shortcuts)),
      ("2-shortcuts-read", model(.shortcuts, read: true)),
      ("3-model-empty", model(.model, provider: "openai")),
      (
        "3-model-tested",
        model(.model, provider: "openai", key: key, connection: .succeeded(.milliseconds(820)))
      ),
      (
        "3-model-rejected",
        model(.model, provider: "openai", key: key, connection: .failed(.model(.unauthorized)))
      ),
      ("4-try", model(.tryIt, read: true)),
    ]
  }
}
