// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import Foundation
import Testing

@testable import DictApp

private let renderDirectory = ProcessInfo.processInfo.environment["DICT_SETTINGS_RENDER_DIR"]
private let showsDemo = ProcessInfo.processInfo.environment["DICT_SETTINGS_DEMO"] == "1"

/// The real Settings window, built but never ordered on screen, except in the demo:
/// `TEST_RUNNER_DICT_SETTINGS_DEMO=1 xcodebuild test … -only-testing:
/// DictAppTests/SettingsWindowTests/demoOnScreen` shows it and walks the tabs. It takes key
/// focus, so hold the machine-wide UI lock while it runs.
@MainActor
struct SettingsWindowTests {
  private func makeController() throws -> SettingsWindowController {
    let suite = "SettingsWindowTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    var preferences = Preferences()
    preferences.model.providerID = "openai"
    PreferencesStore(defaults: defaults).save(preferences)
    let controller = SettingsWindowController(
      model: SettingsModel(
        defaults: defaults, secrets: InMemorySecretStore(["openai": "sk-sample"])),
      hotkeys: HotkeyCenter(defaults: defaults))
    controller.prepare()
    return controller
  }

  @Test func windowTakesTheHeightAndTitleOfEachPane() throws {
    let controller = try makeController()
    let window = try #require(controller.window)
    #expect(!window.isVisible)

    var heights: [SettingsPane: CGFloat] = [:]
    for pane in SettingsPane.allCases {
      controller.select(pane)
      window.contentView?.layoutSubtreeIfNeeded()
      let content = window.contentRect(forFrameRect: window.frame)
      #expect(content.width == SettingsPane.width, "\(pane)")
      #expect(content.height > 100, "\(pane)")
      #expect(window.title == pane.title)
      heights[pane] = content.height
    }
    // The model pane with a provider is the tallest; the window follows each pane.
    #expect(heights[.model, default: 0] > heights[.shortcuts, default: 0])
    #expect(!window.isVisible)
  }

  @Test func closingSavesTheKeyBeingEdited() throws {
    let controller = try makeController()
    controller.model.keyDraft = "sk-edited"

    controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

    #expect(controller.model.keyDraft == "sk-edited")
    #expect(controller.model.setupIssue == nil)
  }

  @Test(.enabled(if: renderDirectory != nil))
  func renderWindow() throws {
    let directory = URL(fileURLWithPath: try #require(renderDirectory))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let language = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? "zh" : "en"
    for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
      let controller = try makeController()
      let window = try #require(controller.window)
      window.appearance = NSAppearance(named: appearance)
      for pane in SettingsPane.allCases {
        controller.select(pane)
        let frame = try #require(window.contentView?.superview)
        frame.layoutSubtreeIfNeeded()
        let bitmap = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
        frame.cacheDisplay(in: frame.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(
          to: directory.appendingPathComponent("\(language)-\(scheme)-window-\(pane.rawValue).png"))
      }
    }
  }

  @Test(.enabled(if: showsDemo))
  func demoOnScreen() async throws {
    // The test host starts in the background, and macOS ignores `NSApp.activate()` from an
    // app that was never active; activation through Launch Services is honoured, like the
    // user's click on the status menu in the real app.
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    _ = try await NSWorkspace.shared.openApplication(
      at: Bundle.main.bundleURL, configuration: configuration)
    let controller = try makeController()
    let window = try #require(controller.window)
    controller.show()
    try await Task.sleep(for: .milliseconds(800))
    // While the screen is locked no window can become key.
    try #require(window.isKeyWindow, "The screen is locked or the window did not open")
    #expect(NSApp.isActive)

    let top = window.frame.maxY
    for pane in SettingsPane.allCases + [.languages] {
      controller.select(pane)
      try await Task.sleep(for: .milliseconds(900))
      #expect(window.frame.maxY == top, "\(pane)")
      #expect(window.title == pane.title)
    }
    window.performClose(nil)
    #expect(!window.isVisible)
  }
}
