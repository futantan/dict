// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
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
    let suite = "MainWindowGalleryTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    var preferences = Preferences()
    preferences.model.providerID = "openai"
    PreferencesStore(defaults: defaults).save(preferences)
    // Saved, not assigned: assigning would register the keys system-wide.
    HotkeyStore(defaults: defaults).save([
      .read: KeyCombo(keyCode: UInt16(kVK_ANSI_A), modifiers: .option),
      .write: KeyCombo(keyCode: UInt16(kVK_ANSI_F), modifiers: .option),
    ])
    let settings = SettingsModel(
      defaults: defaults, secrets: InMemorySecretStore(["openai": "sk-proj-sample-not-a-real-key"]))
    settings.showConnection(.checked(.translated(after: .milliseconds(820))))
    let services = SettingsServices(
      appName: "Dict", version: "1.4.0", accessibilityGranted: { true },
      voice: {
        VoiceChoice(
          voice: VoiceInfo(
            identifier: "com.apple.voice.compact.en-US.Ava", name: "Ava", language: "en-US",
            quality: .compact),
          hint: .higherQuality)
      },
      checkForUpdates: {}, canCheckForUpdates: { true })
    let context = MainWindowContext(
      navigation: MainNavigation(), data: data, settings: settings,
      hotkeys: HotkeyCenter(defaults: defaults), services: services, lookUp: { _, _ in })
    return MainWindowController(context: context)
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
      ("history", sample, { $0.section = .history }),
    ]
    for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
      for (name, data, navigate) in states {
        let controller = try Self.makeController(data: data)
        let window = try #require(controller.window)
        window.appearance = NSAppearance(named: appearance)
        window.setContentSize(WindowLayout.defaultSize)
        navigate(controller.context.navigation)
        let png = try #require(Self.render(window))
        try png.write(to: directory.appendingPathComponent("\(language)-\(scheme)-\(name).png"))
      }
    }
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
