// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import Foundation
import Testing

@testable import DictApp

/// The window around the onboarding steps, laid out offscreen; nothing is shown.
@MainActor
struct OnboardingWindowTests {
  /// The sample panel goes right below the sample box, whose top is in the window's upper half.
  @Test func sampleAnchorIsTheSampleOnScreen() async throws {
    let suite = "OnboardingWindowTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    let model = OnboardingModel(
      hotkeys: HotkeyCenter(defaults: defaults),
      settings: SettingsModel(defaults: defaults, secrets: InMemorySecretStore()),
      permissions: PermissionStatus(accessibility: true, postEvent: true), defaults: defaults)
    model.step = .tryIt
    let controller = OnboardingWindowController(
      model: model, appName: "Dict", refreshPermissions: {})
    let window = try #require(controller.window)
    let content = try #require(window.contentView)
    // On screen the hosting controller sizes the window; offscreen it is done here.
    window.setContentSize(content.fittingSize)
    window.center()
    for _ in 0..<5 where model.sampleFrame == .zero {
      content.layoutSubtreeIfNeeded()
      await Task.yield()
    }

    guard case .selection(let rect) = controller.sampleAnchor() else {
      Issue.record("expected the sample's rectangle, got \(controller.sampleAnchor())")
      return
    }
    #expect(window.frame.contains(rect))
    #expect(rect.maxY > window.frame.midY)
    #expect(rect.maxY < window.contentLayoutRect.maxY + window.frame.minY - 24)
    #expect(rect.width > OnboardingView.width - 60)
  }
}
