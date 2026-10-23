// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Testing

@testable import DictApp

/// The onboarding steps: accessibility, the Read shortcut, a skippable model, the sample.
@MainActor
struct OnboardingModelTests {
  private let off = PermissionStatus(accessibility: false, postEvent: false)
  private let on = PermissionStatus(accessibility: true, postEvent: true)
  private let combo = KeyCombo(keyCode: 2, modifiers: [.control, .option])

  private func defaults() -> UserDefaults {
    .scratch("OnboardingModelTests")
  }

  private func model(
    permissions: PermissionStatus, defaults: UserDefaults,
    secrets: InMemorySecretStore = InMemorySecretStore(),
    shortcuts: [HotkeyRole: KeyCombo] = [:]
  ) -> OnboardingModel {
    HotkeyStore(defaults: defaults).save(shortcuts)
    return OnboardingModel(
      hotkeys: HotkeyCenter(defaults: defaults),
      settings: SettingsModel(defaults: defaults, secrets: secrets), permissions: permissions,
      defaults: defaults)
  }

  @Test func stepsAreInOrder() {
    #expect(OnboardingStep.allCases == [.accessibility, .shortcuts, .model, .tryIt])
  }

  @Test func grantingAccessibilityMovesOnByItself() {
    let model = model(permissions: off, defaults: defaults())
    #expect(model.needsPermissionPolling)

    #expect(model.permissionsChanged(on))

    #expect(model.step == .shortcuts)
    #expect(!model.needsPermissionPolling)
  }

  @Test func aGrantOnALaterStepDoesNotMove() {
    let model = model(permissions: off, defaults: defaults())
    model.step = .model
    #expect(!model.permissionsChanged(on))
    #expect(model.step == .model)
    #expect(!model.needsPermissionPolling)
  }

  @Test func anUnchangedReadingDoesNotMove() {
    let model = model(permissions: off, defaults: defaults())
    #expect(!model.permissionsChanged(off))
    #expect(model.step == .accessibility)
    #expect(model.needsPermissionPolling)
  }

  @Test(arguments: [
    ([:], false),
    ([HotkeyRole.write: KeyCombo(keyCode: 3, modifiers: [.control, .option])], false),
    ([.read: KeyCombo(keyCode: 2, modifiers: [.control, .option])], true),
  ])
  func shortcutsStepNeedsOnlyTheReadShortcut(shortcuts: [HotkeyRole: KeyCombo], continues: Bool) {
    let model = model(permissions: on, defaults: defaults(), shortcuts: shortcuts)
    model.step = .shortcuts
    #expect(model.canContinue == continues)
    model.goForward()
    #expect(model.step == (continues ? .model : .shortcuts))
  }

  /// Arriving at the model step picks the first provider, so the key field is there.
  @Test func modelStepStartsWithTheFirstProvider() {
    let model = model(permissions: on, defaults: defaults(), shortcuts: [.read: combo])
    model.step = .shortcuts
    model.goForward()

    #expect(model.step == .model)
    #expect(model.settings.preferences.model.providerID == model.settings.presets.first?.id)
    #expect(!model.hasModel)
    #expect(model.isSkipping)
  }

  /// "Not Now" moves on without a key.
  @Test func modelStepCanBeSkipped() {
    let model = model(permissions: on, defaults: defaults())
    model.step = .model
    model.settings.selectProvider("openai")
    #expect(model.canContinue)

    model.goForward()

    #expect(model.step == .tryIt)
    #expect(!model.hasModel)
  }

  /// Continue with a key saves it, the same way leaving Settings does.
  @Test func continuingSavesTheKey() throws {
    let secrets = InMemorySecretStore()
    let model = model(permissions: on, defaults: defaults(), secrets: secrets)
    model.step = .model
    model.settings.selectProvider("openai")
    model.settings.keyDraft = "sk-onboarding-test"
    #expect(model.hasModel)
    #expect(!model.isSkipping)

    model.goForward()

    #expect(model.step == .tryIt)
    #expect(secrets.secret(for: "openai") == "sk-onboarding-test")
  }

  @Test func doneRecordsCompletion() {
    let defaults = defaults()
    let model = model(permissions: on, defaults: defaults)
    var finished = false
    model.finish = { finished = true }
    model.step = .tryIt
    #expect(!model.isCompleted)

    model.goForward()

    #expect(finished)
    #expect(model.isCompleted)
  }

  @Test func backGoesOneStep() {
    let model = model(permissions: on, defaults: defaults())
    model.step = .tryIt
    model.goBack()
    #expect(model.step == .model)
    model.step = .accessibility
    model.goBack()
    #expect(model.step == .accessibility)
  }
}

struct ReopenTargetTests {
  @Test func unfinishedOnboardingComesBackElseSettings() {
    #expect(ReopenTarget(onboardingCompleted: false) == .onboarding)
    #expect(ReopenTarget(onboardingCompleted: true) == .mainWindow)
  }
}
