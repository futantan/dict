// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// The first-run steps (architecture 11.4): accessibility, the "read" shortcut, a model with
/// the user's own API key (skippable), and a sample translation in the real panel.
enum OnboardingStep: Int, CaseIterable, Sendable {
  case accessibility, shortcuts, model, tryIt
}

/// State behind the onboarding window.
@MainActor
@Observable
final class OnboardingModel {
  static let completedKey = "onboarding.completed"

  /// English on purpose: the default pair translates it into the user's language. It is
  /// sample content, not interface text.
  static let sample =
    "The best tools disappear into the work: you notice them only when they get in your way."

  var step: OnboardingStep = .accessibility
  private(set) var permissions: PermissionStatus

  let hotkeys: HotkeyCenter
  /// The same model as the Settings window, so the key, provider and "Test" work alike.
  let settings: SettingsModel
  @ObservationIgnored var openAccessibilitySettings: () -> Void = {}
  /// Shows `sample` translated in the result panel.
  @ObservationIgnored var translateSample: () -> Void = {}
  /// Where the sample is, in the window's SwiftUI global coordinates; the panel goes below.
  @ObservationIgnored var sampleFrame = CGRect.zero
  @ObservationIgnored var finish: () -> Void = {}
  @ObservationIgnored private let defaults: UserDefaults

  init(
    hotkeys: HotkeyCenter, settings: SettingsModel, permissions: PermissionStatus,
    defaults: UserDefaults = .standard
  ) {
    self.hotkeys = hotkeys
    self.settings = settings
    self.permissions = permissions
    self.defaults = defaults
  }

  var isCompleted: Bool { defaults.bool(forKey: Self.completedKey) }

  /// Whether Continue (or Done) is available on the current step.
  var canContinue: Bool {
    switch step {
    // The permission can be granted later; the panel explains it when it is missing.
    case .accessibility: true
    case .shortcuts: HotkeyStepView.isComplete(hotkeys)
    // Skippable: "Not Now" stands in for Continue until a model is set up.
    case .model, .tryIt: true
    }
  }

  /// A provider is chosen and nothing it needs is missing.
  var hasModel: Bool {
    settings.selectedPreset != nil && settings.setupIssue == nil
  }

  /// The model step offers "Not Now" instead of Continue until a model is set up.
  var isSkipping: Bool { step == .model && !hasModel }

  /// Polling stands in for the system's change notification, which may not arrive.
  var needsPermissionPolling: Bool { step == .accessibility && !permissions.accessibility }

  func goForward() {
    guard canContinue else { return }
    if step == .model { settings.commitKey() }
    if let next = OnboardingStep(rawValue: step.rawValue + 1) {
      step = next
      // The key field shows only for a provider; most people want the first preset.
      if next == .model, settings.selectedPreset == nil, let first = settings.presets.first {
        settings.selectProvider(first.id)
      }
    } else {
      defaults.set(true, forKey: Self.completedKey)
      finish()
    }
  }

  func goBack() {
    if let previous = OnboardingStep(rawValue: step.rawValue - 1) { step = previous }
  }

  /// A fresh permission reading. Turning accessibility on moves past its step by itself;
  /// returns true then, so the window can come back to the front.
  @discardableResult
  func permissionsChanged(_ status: PermissionStatus) -> Bool {
    let wasGranted = permissions.accessibility
    permissions = status
    guard step == .accessibility, status.accessibility, !wasGranted else { return false }
    goForward()
    return true
  }
}
