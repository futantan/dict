// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import Foundation
import Testing

@testable import DictApp

private let liveKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
private let isEnabled =
  ProcessInfo.processInfo.environment["DICT_ONBOARDING_LIVE"] == "1" && liveKey?.isEmpty == false

/// The onboarding's model step and sample against the real OpenAI API: two tiny calls. The key
/// goes to an in-memory store, never to the Keychain or disk. The sample shows the real panel
/// and takes key focus, so hold the machine-wide UI lock while it runs:
///
/// `bash -c 'set -a; . ./.env; set +a; TEST_RUNNER_DICT_ONBOARDING_LIVE=1
/// TEST_RUNNER_OPENAI_API_KEY="$OPENAI_API_KEY" xcodebuild test …
/// -only-testing:DictAppTests/OnboardingLiveTests'`
@MainActor
@Suite(.enabled(if: isEnabled), .serialized)
struct OnboardingLiveTests {
  private func onboarding() throws -> OnboardingModel {
    let suite = "OnboardingLiveTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    HotkeyStore(defaults: defaults).save([
      .read: KeyCombo(keyCode: 2, modifiers: [.control, .option])
    ])
    let model = OnboardingModel(
      hotkeys: HotkeyCenter(defaults: defaults),
      settings: SettingsModel(defaults: defaults, secrets: InMemorySecretStore()),
      permissions: PermissionStatus(accessibility: true, postEvent: true), defaults: defaults)
    model.step = .shortcuts
    model.goForward()
    try #require(model.step == .model)
    model.settings.keyDraft = try #require(liveKey)
    return model
  }

  /// Step 3: the first provider is preselected; a pasted key passes "Test".
  @Test func testButtonConnects() async throws {
    let model = try onboarding()
    model.settings.testConnection()
    for _ in 0..<600 where model.settings.connection.isTesting {
      try await Task.sleep(for: .milliseconds(50))
    }
    guard case .checked(let report) = model.settings.connection, report.translation == .passed,
      let elapsed = report.firstContent
    else {
      Issue.record("Expected success, got \(model.settings.connection)")
      return
    }
    print("onboarding test button: connected in \(elapsed)")
  }

  /// Step 4: with the key saved by Continue, the sample is translated in the real panel.
  @Test func sampleIsTranslatedInThePanel() async throws {
    let finder = try #require(
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first)
    finder.activate()
    try await Task.sleep(for: .milliseconds(500))
    try #require(
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.loginwindow",
      "The screen is locked")

    let secrets = InMemorySecretStore()
    let suite = "OnboardingLiveTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    let settings = SettingsModel(defaults: defaults, secrets: secrets)
    settings.selectProvider("openai")
    settings.keyDraft = try #require(liveKey)
    settings.commitKey()

    let panel = PanelController()
    defer { panel.hide() }
    let presets = settings.presets
    let coordinator = SessionCoordinator(
      reader: NoReader(), panel: panel,
      environment: SessionCoordinator.Environment(
        makeTranslator: {
          let model = configuredModel(
            PreferencesStore(defaults: defaults).load().model, presets: presets, secrets: secrets)
          return TranslationEngine(
            model: model.map {
              ModelTranslator(
                model: ChatCompletionsModel(
                  endpoint: $0.configuration.endpoint, rules: $0.configuration.rules,
                  apiKey: $0.apiKey))
            })
        },
        languagePair: { LanguagePair() },
        refreshPermissions: { PermissionStatus(accessibility: true, postEvent: true) },
        permissionNotice: { _ in PanelNotice(title: "") },
        performPermissionAction: { _ in false },
        openSettings: {},
        mouseLocation: { NSEvent.mouseLocation },
        makeProofreader: { nil },
        replaceWriter: SystemReplaceWriter(
          system: LiveReplaceSystem(queue: AXQueue(), clipboard: ClipboardGateway())),
        showToast: { _, _ in }))

    coordinator.translateSample(OnboardingModel.sample, near: .none)
    #expect(panel.isVisible)
    #expect(panel.window.isKeyWindow)
    await coordinator.settle()

    guard case .result(let text) = panel.state.phase else {
      Issue.record("expected a result, got \(panel.state.phase)")
      return
    }
    print("onboarding sample: \(text)")
    #expect(text.unicodeScalars.contains { $0.properties.isIdeographic })
    #expect(panel.state.note == nil)
  }
}

/// The sample never reads a selection.
@MainActor
private final class NoReader: SelectionReader {
  func capture(
    policy: ClipboardPolicy, beforeFallback: () -> Void
  ) async -> Result<Selection, CaptureFailure> {
    Issue.record("the sample must not capture")
    return .failure(.ownApp)
  }
}
