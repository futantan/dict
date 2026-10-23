// SPDX-License-Identifier: GPL-3.0-or-later

import Observation

/// The sidebar's items, in order (Design/main-app/README.md). Each is one page view in
/// `MainWindowView.page(for:)`.
enum MainSection: String, CaseIterable {
  case today, history, saved, review, settings

  var title: String {
    switch self {
    case .today:
      String(localized: "Today", table: "MainWindow", comment: "Sidebar item and page title")
    case .history:
      String(localized: "History", table: "MainWindow", comment: "Sidebar item and page title")
    case .saved:
      String(localized: "Word List", table: "MainWindow", comment: "Sidebar item and page title")
    case .review:
      String(localized: "Review", table: "MainWindow", comment: "Sidebar item and page title")
    case .settings:
      String(localized: "Settings", table: "MainWindow", comment: "Sidebar item and page title")
    }
  }

  /// Outlined symbols at the panel's light weight, close to the mockups' strokes.
  var symbol: String {
    switch self {
    case .today: "sun.max"
    case .history: "clock.arrow.circlepath"
    case .saved: "star"
    case .review: "rectangle.on.rectangle"
    case .settings: "gearshape"
    }
  }
}

/// The sections of the settings page, in order (Design/main-app/settings.html).
enum SettingsSection: String, CaseIterable {
  case general, languages, model, shortcuts, writing, voice, permissions, privacy, about

  var title: String {
    switch self {
    case .general:
      String(localized: "General", table: "Settings", comment: "Settings section title")
    case .languages:
      String(localized: "Languages", table: "Settings", comment: "Settings section title")
    case .model:
      String(localized: "Model", table: "Settings", comment: "Settings section title")
    case .shortcuts:
      String(localized: "Shortcuts", table: "Settings", comment: "Settings section title")
    case .writing:
      String(localized: "Writing", table: "Settings", comment: "Settings section title")
    case .voice:
      String(localized: "Pronunciation", table: "Settings", comment: "Settings section title")
    case .permissions:
      String(localized: "Permissions", table: "Settings", comment: "Settings section title")
    case .privacy:
      String(localized: "Data & Privacy", table: "Settings", comment: "Settings section title")
    case .about:
      String(localized: "About", table: "Settings", comment: "Settings section title")
    }
  }
}

/// Where the window is: the page, and on the settings page the section scrolled to.
@MainActor @Observable
final class MainNavigation {
  var section: MainSection
  /// The settings section to scroll to; set it with `show(_:)` so the page scrolls even when
  /// it is the same one again.
  private(set) var settingsSection: SettingsSection?
  /// Bumped to move the focus to the search field (⌘K).
  private(set) var searchFocusRequest = 0

  init(section: MainSection = .today) {
    self.section = section
  }

  func show(_ settings: SettingsSection) {
    section = .settings
    settingsSection = settings
  }

  /// The settings page scrolled to `settingsSection`; it is cleared so the same section can
  /// be asked for again.
  func didScrollToSettingsSection() {
    settingsSection = nil
  }

  func focusSearch() {
    section = .today
    searchFocusRequest += 1
  }

  // MARK: - Review

  /// The term a review was asked to start with; the review page starts its session with it,
  /// due or not, then the rest due, and clears it with `didStartReview()`.
  private(set) var reviewTermRequest: Int64?

  /// 「现在复习」 on 生词本: opens 复习 on a new session with `termID` first.
  func startReview(with termID: Int64) {
    section = .review
    reviewTermRequest = termID
  }

  /// The review page took `reviewTermRequest`; it is cleared so the same term can be asked
  /// for again.
  func didStartReview() {
    reviewTermRequest = nil
  }
}
