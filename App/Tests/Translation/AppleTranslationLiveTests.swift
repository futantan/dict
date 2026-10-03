// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import Foundation
import Testing
import Translation

@testable import DictApp

private let isEnabled = ProcessInfo.processInfo.environment["DICT_TRANSLATION_LIVE"] == "1"
private let english = Locale.Language(identifier: "en")
private let chinese = Locale.Language(identifier: "zh-Hans")

/// Apple Translation in the app's real form: the test host is the `LSUIElement` app itself,
/// and the panel route goes through the non-activating result panel. Opt-in, because it shows
/// the panel and takes key focus; hold the machine-wide UI lock while it runs:
///
/// `TEST_RUNNER_DICT_TRANSLATION_LIVE=1 xcodebuild test … -only-testing:DictAppTests/AppleTranslationLiveTests`
@MainActor
@Suite(.serialized, .enabled(if: isEnabled))
struct AppleTranslationLiveTests {
  @Test func reportsLanguageStatus() async {
    let availability = LanguageAvailability()
    for (source, target) in [("en", "zh-Hans"), ("zh-Hans", "en"), ("en", "ja"), ("en", "en")] {
      let status = await availability.status(
        from: Locale.Language(identifier: source), to: Locale.Language(identifier: target))
      print("apple translation status \(source) → \(target): \(status)")
    }
  }

  /// macOS 26 constructs a session for installed languages without any view.
  @Test func directSessionWithoutAWindow() async throws {
    guard #available(macOS 26, *) else { return }
    try #require(
      await LanguageAvailability().status(from: english, to: chinese) == .installed,
      "Download English and Chinese in Settings → Language & Region → Translation Languages")
    let text = try await withTimeout {
      try await AppleTranslator.shared.translation(
        of: "Good morning, how are you?", from: english, to: chinese)
    }
    print("direct session: \(text)")
    #expect(text.unicodeScalars.contains { $0.properties.isIdeographic })
  }

  /// The macOS 15 route: `.translationTask` on the visible, non-activating panel.
  @Test func panelSessionInTheNonActivatingPanel() async throws {
    let finder = try #require(
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first)
    finder.activate()
    try await Task.sleep(for: .milliseconds(500))
    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    try #require(front != "com.apple.loginwindow", "The screen is locked")

    let controller = PanelController()
    let source = "The meeting has been moved to Thursday afternoon."
    controller.show(PanelState(source: source, phase: .generating("")), near: .none)
    defer { controller.hide() }

    let text = try await withTimeout {
      try await AppleTranslator.shared.translation(
        of: source, from: english, to: chinese, route: .panel)
    }
    print("panel session: \(text)")
    #expect(text.unicodeScalars.contains { $0.properties.isIdeographic })
    #expect(!NSApp.isActive, "Dict must not become the active app")
    #expect(NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder")

    // A second request for the same pair needs a new session from the same modifier.
    let again = try await withTimeout {
      try await AppleTranslator.shared.translation(
        of: "See you tomorrow.", from: english, to: chinese, route: .panel)
    }
    print("panel session again: \(again)")
    #expect(again.unicodeScalars.contains { $0.properties.isIdeographic })
  }

  /// The zero-configuration path end to end: no model, the engine updates the real panel.
  @Test func engineWithoutAModelUpdatesThePanel() async throws {
    let finder = try #require(
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first)
    finder.activate()
    try await Task.sleep(for: .milliseconds(500))
    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    try #require(front != "com.apple.loginwindow", "The screen is locked")

    let controller = PanelController()
    let source = "这个周末我们去爬山吧。"
    controller.show(PanelState(source: source, phase: .reading), near: .none)
    defer { controller.hide() }

    let engine = TranslationEngine()
    try await withTimeout {
      await engine.translate(source, direction: .intoLearning, pair: LanguagePair()) {
        controller.update($0)
      }
    }
    print("engine result: \(controller.state)")
    guard case .result(let text) = controller.state.phase else {
      Issue.record("expected a result, got \(controller.state.phase)")
      return
    }
    #expect(text.contains { $0.isLetter && $0.isASCII })
    #expect(!NSApp.isActive)
  }
}

/// Cancels `operation` after 20 seconds instead of hanging when no session ever arrives.
@MainActor
private func withTimeout<T: Sendable>(
  _ operation: @escaping @MainActor @Sendable () async throws -> T
) async throws -> T {
  let task = Task { @MainActor in try await operation() }
  let timer = Task {
    try await Task.sleep(for: .seconds(20))
    print("timed out after 20 s")
    task.cancel()
  }
  defer { timer.cancel() }
  return try await task.value
}
