// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Observation
import Translation

/// The first-run steps that M1 needs (architecture 11.4): accessibility, the two shortcuts,
/// and Apple Translation's languages. Languages and a model live in Settings.
enum OnboardingStep: Int, CaseIterable, Sendable {
  case accessibility, shortcuts, translation
}

/// Whether Apple Translation can translate the user's pair on this Mac.
enum LanguagePackState: Sendable, Equatable {
  case checking
  case installed
  case needsDownload
  /// Waiting for the system's download prompt or the download itself.
  case downloading
  case unsupported
}

/// State behind the onboarding window.
@MainActor
@Observable
final class OnboardingModel {
  static let completedKey = "onboarding.completed"

  /// The model whose window is open; `.translationTask` reports back to it.
  @ObservationIgnored static weak var active: OnboardingModel?

  var step: OnboardingStep = .accessibility
  private(set) var permissions: PermissionStatus
  private(set) var pair = LanguagePair()
  private(set) var languages = LanguagePackState.checking
  /// Watched by `.translationTask`; setting it asks for the session that downloads languages.
  private(set) var preparation: TranslationSession.Configuration?

  let hotkeys: HotkeyCenter
  @ObservationIgnored var openAccessibilitySettings: () -> Void = {}
  @ObservationIgnored var openSettings: () -> Void = {}
  @ObservationIgnored var finish: () -> Void = {}
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let languageStatus:
    @Sendable (Locale.Language, Locale.Language) async -> AppleTranslationAvailability

  init(
    hotkeys: HotkeyCenter, permissions: PermissionStatus, defaults: UserDefaults = .standard,
    languageStatus:
      @escaping @Sendable (Locale.Language, Locale.Language) async ->
      AppleTranslationAvailability = { await AppleTranslator.availability(from: $0, to: $1) }
  ) {
    self.hotkeys = hotkeys
    self.permissions = permissions
    self.defaults = defaults
    self.languageStatus = languageStatus
  }

  var isCompleted: Bool { defaults.bool(forKey: Self.completedKey) }

  /// Whether Continue (or Done) is available on the current step.
  var canContinue: Bool {
    switch step {
    // The permission can be granted later; the panel explains it when it is missing.
    case .accessibility: true
    case .shortcuts: HotkeyStepView.isComplete(hotkeys)
    case .translation: true
    }
  }

  func goForward() {
    guard canContinue else { return }
    if let next = OnboardingStep(rawValue: step.rawValue + 1) {
      step = next
    } else {
      defaults.set(true, forKey: Self.completedKey)
      finish()
    }
  }

  func goBack() {
    if let previous = OnboardingStep(rawValue: step.rawValue - 1) { step = previous }
  }

  /// A fresh permission reading. Turning accessibility on moves past its step by itself.
  func permissionsChanged(_ status: PermissionStatus) {
    let wasGranted = permissions.accessibility
    permissions = status
    if step == .accessibility, status.accessibility, !wasGranted { goForward() }
  }

  /// Reads the language pair from the preferences and checks its languages.
  func refreshLanguages(_ pair: LanguagePair) async {
    self.pair = pair
    if languages != .downloading { languages = .checking }
    let status = await languageStatus(pair.learning, pair.mine)
    guard pair == self.pair else { return }
    switch status {
    case .installed: languages = .installed
    case .unsupported: languages = .unsupported
    case .needsDownload: if languages != .downloading { languages = .needsDownload }
    }
  }

  /// Asks Apple Translation for a session in this window, which shows the system's download
  /// prompt (architecture 6.5).
  func downloadLanguages() {
    languages = .downloading
    Self.active = self
    if var current = preparation, current.source == pair.learning, current.target == pair.mine {
      current.invalidate()
      preparation = current
    } else {
      preparation = TranslationSession.Configuration(source: pair.learning, target: pair.mine)
    }
  }

  /// Called by `.translationTask`. Nonisolated, so the session stays in the modifier's task.
  nonisolated static func prepare(_ session: TranslationSession) async {
    do {
      try await session.prepareTranslation()
      Log.model.info("onboarding: translation languages prepared")
    } catch {
      Log.model.error(
        "onboarding: preparing translation failed: \(String(describing: type(of: error)), privacy: .public)"
      )
    }
    await MainActor.run { active?.preparationEnded() }
  }

  private func preparationEnded() {
    languages = .checking
    Task { await refreshLanguages(pair) }
  }
}
