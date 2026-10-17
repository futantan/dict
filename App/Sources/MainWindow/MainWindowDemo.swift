// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
  import AppKit
  import Carbon.HIToolbox
  import DictCore
  import Foundation

  extension MainWindowGallery {
    /// A window over `data` with settings that never touch the user's defaults or keychain:
    /// a defaults suite of its own and a placeholder key in memory.
    static func makeController(data: WindowData) -> MainWindowController {
      let suite = "MainWindowGallery.\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: suite) ?? UserDefaults()
      defaults.removePersistentDomain(forName: suite)
      var preferences = Preferences()
      preferences.model.providerID = "openai"
      PreferencesStore(defaults: defaults).save(preferences)
      // Saved, not assigned: assigning would register the keys system-wide.
      HotkeyStore(defaults: defaults).save([
        .read: KeyCombo(keyCode: UInt16(kVK_ANSI_A), modifiers: .option),
        .write: KeyCombo(keyCode: UInt16(kVK_ANSI_F), modifiers: .option),
      ])
      let settings = SettingsModel(
        defaults: defaults,
        secrets: InMemorySecretStore(["openai": "sk-proj-sample-not-a-real-key"]))
      settings.showConnection(.checked(.translated(after: .milliseconds(820))))
      let services = SettingsServices(
        appName: "Dict", version: "1.4.0", accessibilityGranted: { true },
        voice: {
          VoiceChoice(
            voice: VoiceInfo(
              identifier: "com.apple.voice.compact.en-US.Ava", name: "Ava", language: "en-US",
              quality: .compact),
            hint: .higherQuality)
        },
        checkForUpdates: {}, canCheckForUpdates: { true })
      let context = MainWindowContext(
        navigation: MainNavigation(), data: data, settings: settings,
        hotkeys: HotkeyCenter(defaults: defaults), services: services, lookUp: { _, _ in },
        history: HistoryServices(lookUpTerm: { lexicon($0, context: $1) }))
      return MainWindowController(context: context, frameName: nil)
    }

    /// The sample data on the Review page after answering `answers`.
    static func reviewingData(answers: [Rating]) async throws -> WindowData {
      let data = try await sampleData()
      await data.review.appear()
      for rating in answers {
        data.review.reveal()
        await data.review.answer(rating)
      }
      return data
    }
  }

  /// `-DictWindowDemo <state>`: the main window on screen over the gallery's sample data, for
  /// checking it as the user sees it without the user's log, defaults or keychain. No
  /// session, shortcuts or model. `-DictWindowDemoWidth <points>` sets the content width and
  /// `-DictWindowDemoCloseAfter <seconds>` closes the window as its close button would.
  @MainActor
  enum MainWindowDemo {
    enum State: String, CaseIterable {
      case today, history, saved, review, settings
      case historyCorrection = "history-correction"
      case reviewRevealed = "review-revealed"
      case settingsModel = "settings-model"
    }

    static func data(for state: State) async throws -> WindowData {
      switch state {
      case .history, .historyCorrection:
        let data = try await MainWindowGallery.sampleData()
        await data.history.reload()
        if state == .historyCorrection {
          data.history.selectedID =
            data.history.items.first {
              if case .sentence(let event) = $0 { event.kind == .corrected } else { false }
            }?.historyID
        }
        return data
      case .review, .reviewRevealed:
        // 3 / 9 as in the mockup.
        let data = try await MainWindowGallery.reviewingData(answers: [.again, .good, .good])
        if state == .reviewRevealed { data.review.reveal() }
        return data
      case .today, .saved, .settings, .settingsModel:
        return try await MainWindowGallery.sampleData()
      }
    }

    static func navigate(_ navigation: MainNavigation, to state: State) {
      switch state {
      case .today: navigation.section = .today
      case .history, .historyCorrection: navigation.section = .history
      case .saved: navigation.section = .saved
      case .review, .reviewRevealed: navigation.section = .review
      case .settings: navigation.section = .settings
      case .settingsModel: navigation.show(.model)
      }
    }

    /// The window on `state`, `width` points wide when given, not yet shown.
    static func makeController(_ state: State, width: Double?) async throws
      -> MainWindowController
    {
      let controller = MainWindowGallery.makeController(data: try await data(for: state))
      if let width, width > 0 {
        controller.window?.setContentSize(
          CGSize(width: width, height: WindowLayout.defaultSize.height))
        controller.window?.center()
      }
      navigate(controller.context.navigation, to: state)
      return controller
    }
  }
#endif
