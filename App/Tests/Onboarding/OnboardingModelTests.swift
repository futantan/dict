// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Testing

@testable import DictApp

@MainActor
struct OnboardingModelTests {
  private let off = PermissionStatus(accessibility: false, postEvent: false)
  private let on = PermissionStatus(accessibility: true, postEvent: true)

  private func defaults() -> UserDefaults {
    let name = "OnboardingModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  private func model(
    permissions: PermissionStatus, defaults: UserDefaults,
    languages: AppleTranslationAvailability = .installed
  ) -> OnboardingModel {
    OnboardingModel(
      hotkeys: HotkeyCenter(defaults: defaults), permissions: permissions, defaults: defaults,
      languageStatus: { _, _ in languages })
  }

  @Test func grantingAccessibilityMovesOnByItself() {
    let model = model(permissions: off, defaults: defaults())
    model.permissionsChanged(on)
    #expect(model.step == .shortcuts)
  }

  @Test func aGrantOnALaterStepDoesNotMove() {
    let model = model(permissions: off, defaults: defaults())
    model.step = .translation
    model.permissionsChanged(on)
    #expect(model.step == .translation)
  }

  @Test func shortcutsStepNeedsBothShortcuts() {
    let defaults = defaults()
    let model = model(permissions: on, defaults: defaults)
    model.step = .shortcuts
    #expect(!model.canContinue)
    model.goForward()
    #expect(model.step == .shortcuts)
  }

  @Test func doneRecordsCompletion() {
    let defaults = defaults()
    let model = model(permissions: on, defaults: defaults)
    var finished = false
    model.finish = { finished = true }
    model.step = .translation
    #expect(!model.isCompleted)

    model.goForward()

    #expect(finished)
    #expect(model.isCompleted)
  }

  @Test(arguments: [
    (AppleTranslationAvailability.installed, LanguagePackState.installed),
    (.needsDownload, .needsDownload),
    (.unsupported, .unsupported),
  ])
  func languageStatusIsShown(status: AppleTranslationAvailability, expected: LanguagePackState)
    async
  {
    let model = model(permissions: on, defaults: defaults(), languages: status)
    await model.refreshLanguages(LanguagePair())
    #expect(model.languages == expected)
  }
}
