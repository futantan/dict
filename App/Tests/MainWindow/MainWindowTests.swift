// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import Foundation
import Testing

@testable import DictApp

@MainActor
struct MainWindowTests {
  /// The window's text reads at 4.5:1 or more on the sidebar and the cards, in either
  /// appearance, as the panel's does on its fill.
  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theWindowsTextIsLegible(_ name: NSAppearance.Name) throws {
    let appearance = try #require(NSAppearance(named: name))
    let pairs: [(String, NSColor, NSColor)] = [
      ("textQuiet on sidebar", Palette.textQuiet, Palette.sidebarFill),
      ("textSecondary on sidebar", Palette.textSecondary, Palette.sidebarFill),
      ("accentOnTint on sidebar item", Palette.accentOnTint, Palette.accentTint),
      ("textPrimary on card", Palette.textPrimary, Palette.cardFill),
      ("textSecondary on card", Palette.textSecondary, Palette.cardFill),
      ("textQuiet on card", Palette.textQuiet, Palette.cardFill),
      ("dangerOnTint", Palette.dangerOnTint, Palette.dangerTint),
    ]
    for (label, text, background) in pairs {
      let ratio = Contrast.ratio(text, on: background, in: appearance)
      #expect(ratio >= 4.5, "\(label) in \(name.rawValue): \(ratio)")
    }
  }

  @Test func presenceFollowsTheDockAndMenuBarSwitches() {
    var preferences = Preferences()
    #expect(AppPresence(preferences) == AppPresence(policy: .regular, statusItem: true))

    preferences.setShowsDockIcon(false)
    #expect(AppPresence(preferences) == AppPresence(policy: .accessory, statusItem: true))

    preferences.setShowsDockIcon(true)
    preferences.setShowsMenuBarIcon(false)
    #expect(AppPresence(preferences) == AppPresence(policy: .regular, statusItem: false))
  }

  @Test func navigationScrollsSettingsOnceAndFocusesTheSearchOnToday() {
    let navigation = MainNavigation()
    #expect(navigation.section == .today)

    navigation.show(.shortcuts)
    #expect(navigation.section == .settings)
    #expect(navigation.settingsSection == .shortcuts)
    navigation.didScrollToSettingsSection()
    #expect(navigation.settingsSection == nil)

    navigation.focusSearch()
    #expect(navigation.section == .today)
    #expect(navigation.searchFocusRequest == 1)
  }

  /// The window's snapshot of the gallery's store, as the Today page and the sidebar show it.
  @Test func dataReadsTodayFromTheStore() async throws {
    let data = try await MainWindowGallery.sampleData()

    #expect(
      data.today.counts
        == DayCounts(terms: 12, lookups: 12, translations: 5, writes: 7, replaced: 6))
    #expect(data.today.due == 9)
    #expect(data.dueCount == 9)
    #expect(data.learningCount == 12)
    #expect(data.today.frequent.map(\.lemma) == ["leverage", "nuance", "tentative"])
    #expect(data.today.recent.count == TodaySnapshot.recentLimit)
    #expect(data.totals.sentences == 12)
  }

  @Test func markingToLearnFromTodayRefreshes() async throws {
    let data = try await MainWindowGallery.sampleData()
    let leverage = try #require(data.today.frequent.first)

    await data.setTier(.learning, termID: leverage.id)

    #expect(data.learningCount == 13)
    #expect(!data.today.frequent.contains { $0.id == leverage.id })
  }

  @Test func clearingEverythingEmptiesThePages() async throws {
    let data = try await MainWindowGallery.sampleData()

    await data.deleteAll()

    #expect(data.today == TodaySnapshot())
    #expect(data.learningCount == 0)
    #expect(data.totals == VocabTotals(terms: 0, sentences: 0))
  }

  @Test func withoutALogThereIsNothingToShow() async {
    let data = MainWindowGallery.unavailableData()
    await data.refresh()

    #expect(!data.isAvailable)
    #expect(data.today == TodaySnapshot())
  }

  @Test func aLookupLineShowsItsMeaningSentenceAppAndTime() async throws {
    let data = try await MainWindowGallery.sampleData()
    let lines = data.today.recent.map {
      ActivityLine(
        $0, now: MainWindowGallery.now, timeZone: MainWindowGallery.timeZone,
        locale: Locale(identifier: "en_US_POSIX"),
        appName: { $0 == "com.apple.Safari" ? "Safari" : nil })
    }

    let run = try #require(lines.first)
    #expect(run.title == "run")
    #expect(run.tag == "v.")
    #expect(run.text == .meaning("经营；管理", sentence: "She ran a small bakery in the old town."))
    #expect(run.detail.hasPrefix("Safari · 2:20"))
    #expect(run.isLearning)

    let correction = try #require(
      lines.first { $0.isEvent && $0.tagTone == .success && $0.termID == nil })
    #expect(correction.detail.hasPrefix("10:18"))
    guard case .diff(let segments) = correction.text else {
      Issue.record("not a diff: \(correction.text)")
      return
    }
    #expect(segments.contains(.changed(from: "have", to: "has")))
  }

  /// Ported from the old Settings window: closing the window saves the key being typed.
  @Test func closingTheWindowSavesTheKeyBeingEdited() async throws {
    let controller = try MainWindowGalleryTests.makeController(
      data: MainWindowGallery.unavailableData())
    var closed = false
    controller.onClose = { closed = true }
    controller.context.settings.keyDraft = "sk-edited"

    controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

    #expect(controller.context.settings.keyDraft == "sk-edited")
    #expect(controller.context.settings.setupIssue == nil)
    #expect(closed)
    #expect(controller.window?.isVisible == false)
  }

  @Test func aLineFromAnotherDayShowsTheDate() {
    let now = MainWindowGallery.now
    let text = ActivityLine.time(
      now.addingTimeInterval(-86_400), now: now, timeZone: MainWindowGallery.timeZone,
      locale: Locale(identifier: "en_US_POSIX"))
    #expect(text.contains("Oct 16"))
  }
}

extension AppPresence {
  fileprivate init(policy: NSApplication.ActivationPolicy, statusItem: Bool) {
    self.init(Preferences())
    activationPolicy = policy
    showsStatusItem = statusItem
  }
}
