// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
  private var statusItem: NSStatusItem?
  private var appName = ProcessInfo.processInfo.processName

  private let hotkeys = HotkeyCenter()
  private let permissions = PermissionMonitor()
  private let panel = PanelController()
  private let guide = PermissionGuide()
  private let presets = (try? ProviderPreset.all()) ?? []
  private var reader: AccessibilitySelectionReader?
  private let speaker = Speaker()
  /// The dictionary layer; nil when the app was built without the dictionary.
  private var lexicon: Lexicon?
  /// The vocabulary log; nil when it could not be opened.
  private var vocab: VocabStore?
  private var coordinator: SessionCoordinator?
  private var onboarding: OnboardingWindowController?
  /// nil when updates are off for this build (`UpdateFeed`).
  private var updater: Updater?
  private var observers: [any NSObjectProtocol] = []
  /// The settings the main window's Settings page and the onboarding window edit.
  private let settings = SettingsModel()
  /// Built on first use, after the session is wired.
  private var mainWindow: MainWindowController?

  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    #if DEBUG
      KeyImport.runIfRequested()
      E2ERunner.startIfRequested()
    #endif
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let identity = AppIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])
    appName = identity?.name ?? appName

    switch LaunchMode.current {
    case .unitTests, .endToEnd:
      // The test host and the e2e runner drive their own objects; no shortcuts or windows,
      // and they stay agents without a Dock icon.
      setStatusItemShown(true)
      return
    case .normal(let onboarding):
      apply(AppPresence(settings.preferences))
      start(showingOnboarding: onboarding)
    }
  }

  /// Opening Dict again while it runs (Dock, Finder, Spotlight, `open`): unfinished
  /// onboarding comes back, else the main window.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
    -> Bool
  {
    // The test host and the e2e runner have no session and show no windows.
    guard coordinator != nil else { return false }
    switch ReopenTarget(onboardingCompleted: onboardingCompleted) {
    case .onboarding: showOnboarding()
    case .mainWindow: openMainWindow()
    }
    return false
  }

  func applicationWillTerminate(_ notification: Notification) {
    hotkeys.stop()
    permissions.stop()
  }

  // MARK: - Wiring

  private func start(showingOnboarding: Bool) {
    let reader = AccessibilitySelectionReader()
    reader.start()
    self.reader = reader
    lexicon = openBundledLexicon()
    vocab = openVocab()
    let coordinator = makeCoordinator(reader: reader)
    self.coordinator = coordinator

    panel.onDismiss = { [weak coordinator] in coordinator?.panelDismissed($0) }
    panel.onSubmit = { [weak coordinator] in coordinator?.submitted($0) }
    panel.onAction = { [weak coordinator] in coordinator?.perform($0) }
    panel.onConfirm = { [weak coordinator] in coordinator?.confirm(anyway: $0) }
    hotkeys.onPress = { [weak coordinator] in coordinator?.hotkeyPressed($0) }
    hotkeys.start()

    permissions.onChange = { [weak self] status, granted in
      self?.coordinator?.permissionsChanged(granted: granted)
      if granted.contains(.accessibility) { self?.hotkeys.accessibilityGranted() }
      // The grant happened in System Settings; bring the window back to show it worked.
      if self?.onboarding?.model.permissionsChanged(status) == true {
        self?.onboarding?.show()
      }
    }
    permissions.start()
    observeOwnWindows()

    // `--no-onboarding` launches in the background for scripts: no window at all.
    if showingOnboarding {
      if onboardingCompleted { openMainWindow() } else { showOnboarding() }
    }
    // Silent: renders one word so the first ⌘P on a card speaks at once (architecture 9).
    let preferences = PreferencesStore(defaults: .standard).load()
    speaker.accent = preferences.accent
    speaker.prewarm(language: preferences.languagePair.learning)
    let info = Bundle.main.infoDictionary ?? [:]
    Log.update.notice(
      "version \(info["CFBundleShortVersionString"] as? String ?? "?", privacy: .public) (\(info["CFBundleVersion"] as? String ?? "?", privacy: .public))"
    )
    updater = Updater.start()
    if let mock = mockModelBaseURL() {
      Log.model.notice("mock model at \(mock, privacy: .public)")
    }
    Log.ui.info(
      "started: accessibility \(self.permissions.status.accessibility, privacy: .public), shortcuts \(self.hotkeys.shortcuts.count, privacy: .public)"
    )
  }

  private func makeCoordinator(reader: AccessibilitySelectionReader) -> SessionCoordinator {
    let presets = presets
    let guide = guide
    return SessionCoordinator(
      reader: reader, panel: panel,
      environment: SessionCoordinator.Environment(
        makeTranslator: {
          makeTranslationEngine(
            PreferencesStore(defaults: .standard).load().model, presets: presets,
            secrets: CachedSecretStore.app)
        },
        languagePair: { PreferencesStore(defaults: .standard).load().languagePair },
        refreshPermissions: { [permissions] in permissions.refresh() },
        permissionNotice: { guide.notice(for: $0) },
        performPermissionAction: { guide.perform($0) },
        openSettings: { [weak self] in self?.openMainWindow(settings: .model) },
        mouseLocation: { NSEvent.mouseLocation },
        makeProofreader: {
          makeProofreader(
            PreferencesStore(defaults: .standard).load().model, presets: presets,
            secrets: CachedSecretStore.app)
        },
        replaceWriter: SystemReplaceWriter(
          system: LiveReplaceSystem(queue: reader.queue, clipboard: reader.clipboard)),
        showToast: { ToastController.shared.show($0, near: $1) },
        lookUpTerm: { [lexicon] term, context in
          await lexicon?.lookup(term, context: context) ?? []
        },
        makeCardMaker: {
          makeCardMaker(
            PreferencesStore(defaults: .standard).load().model, presets: presets,
            secrets: CachedSecretStore.app)
        },
        vocab: vocab,
        accent: { PreferencesStore(defaults: .standard).load().accent },
        pronounce: { [speaker] text, language, rate in
          speaker.accent = PreferencesStore(defaults: .standard).load().accent
          speaker.say(text, language: language, rate: rate)
        },
        makeTranslateOut: {
          makeTranslateOutEngine(
            PreferencesStore(defaults: .standard).load().model, presets: presets,
            secrets: CachedSecretStore.app)
        },
        keepsFormatting: { PreferencesStore(defaults: .standard).load().keepsFormatting }))
  }

  /// The vocabulary log in Application Support (architecture 8.2); nil, logged, when it
  /// cannot be opened, and then nothing is recorded.
  private func openVocab() -> VocabStore? {
    do {
      let support = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let bundleID = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
      return try VocabStore(url: vocabURL(applicationSupport: support, bundleID: bundleID))
    } catch {
      Log.store.error("vocabulary log not opened: \(String(describing: error), privacy: .public)")
      return nil
    }
  }

  /// Opening Settings or the onboarding window ends the session (architecture 11.4), and
  /// either becoming key re-reads the permissions (architecture 3.8).
  private func observeOwnWindows() {
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
      ) { [weak self] notification in
        let window = notification.object as? NSWindow
        MainActor.assumeIsolated {
          guard let self, let window, window !== self.panel.window else { return }
          self.coordinator?.end()
          self.permissions.refresh()
        }
      })
  }

  // MARK: - Main window

  private func openMainWindow(settings section: SettingsSection? = nil) {
    let controller = mainWindow ?? makeMainWindow()
    mainWindow = controller
    if let section {
      controller.show(settings: section)
    } else {
      controller.show()
    }
  }

  private func makeMainWindow() -> MainWindowController {
    let data = WindowData(vocab: vocab)
    var services = SettingsServices(
      appName: appName,
      version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "",
      loginItem: .mainApp,
      accessibilityGranted: { [permissions] in permissions.refresh().accessibility },
      openAccessibilitySettings: { [guide] in
        _ = guide.perform(PermissionGuide.ActionID.openSettings)
      },
      voice: { [speaker, settings] in
        speaker.voiceChoice(for: settings.preferences.languagePair.learning)
      },
      openVoiceSettings: { NSWorkspace.shared.open(Self.voiceSettingsURL) },
      canCheckForUpdates: { [weak self] in self?.updater?.canCheckForUpdates ?? false },
      presenceChanged: { [weak self] in self?.apply(AppPresence($0)) },
      export: { [weak self] in self?.exportRecords() })
    if updater != nil {
      services.checkForUpdates = { [weak self] in self?.updater?.checkForUpdates() }
    }
    let navigation = MainNavigation()
    let context = MainWindowContext(
      navigation: navigation, data: data, settings: settings, hotkeys: hotkeys,
      services: services,
      lookUp: { [weak self] text, rect in self?.lookUpFromWindow(text, fieldRect: rect) })
    let controller = MainWindowController(context: context)
    controller.onClose = { [weak self] in
      guard let self, !self.settings.preferences.keepsRunningAfterClose else { return }
      NSApp.terminate(nil)
    }
    return controller
  }

  /// System Settings → Accessibility → Spoken Content, where voices are downloaded.
  private static let voiceSettingsURL =
    URL(
      string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpeechSettings")
    ?? URL(fileURLWithPath: "/System/Applications/System Settings.app")

  private func lookUpFromWindow(_ text: String, fieldRect: CGRect) {
    let anchor = mainWindow?.screenRect(ofContentRect: fieldRect).map(PanelAnchor.selection)
    coordinator?.lookUpTyped(text, near: anchor ?? .mouse(NSEvent.mouseLocation))
  }

  /// 「导出…」: the Anki TSV of every term, saved where the user says.
  private func exportRecords() {
    guard let window = mainWindow?.window, let data = mainWindow?.context.data else { return }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "\(appName).txt"
    panel.allowedContentTypes = [.tabSeparatedText]
    panel.beginSheetModal(for: window) { response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in
        do {
          try await data.exportAnki()?.write(to: url, options: .atomic)
        } catch {
          Log.store.error("export failed: \(String(describing: error), privacy: .public)")
          let alert = NSAlert()
          alert.messageText = SettingsText.exportFailed
          alert.informativeText = error.localizedDescription
          await alert.beginSheetModal(for: window)
        }
      }
    }
  }

  // MARK: - Dock and menu bar

  /// Shows the Dock icon and the menu bar icon as the settings say. Becoming a regular app
  /// from an agent needs activating again before the Dock icon and the menu bar appear.
  private func apply(_ presence: AppPresence) {
    setStatusItemShown(presence.showsStatusItem)
    if NSApp.mainMenu == nil { NSApp.mainMenu = MainMenu.make(appName: appName) }
    guard NSApp.activationPolicy() != presence.activationPolicy else { return }
    NSApp.setActivationPolicy(presence.activationPolicy)
    if presence.activationPolicy == .regular,
      NSApp.isActive || mainWindow?.window?.isVisible == true
    {
      NSApp.activateFromFrontApp()
    }
  }

  private func setStatusItemShown(_ shown: Bool) {
    if shown, statusItem == nil {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      item.button?.image = NSImage(
        systemSymbolName: "character.book.closed", accessibilityDescription: appName)
      item.menu = makeMenu()
      statusItem = item
    } else if !shown, let item = statusItem {
      NSStatusBar.system.removeStatusItem(item)
      statusItem = nil
    }
  }

  // MARK: - Onboarding

  private var onboardingCompleted: Bool {
    UserDefaults.standard.bool(forKey: OnboardingModel.completedKey)
  }

  private func showOnboarding() {
    if onboarding == nil {
      let model = OnboardingModel(
        hotkeys: hotkeys, settings: settings, permissions: permissions.status)
      model.openAccessibilitySettings = { [guide] in
        _ = guide.perform(PermissionGuide.ActionID.openSettings)
      }
      model.translateSample = { [weak self] in
        guard let self, let onboarding = self.onboarding else { return }
        self.coordinator?.translateSample(OnboardingModel.sample, near: onboarding.sampleAnchor())
      }
      onboarding = OnboardingWindowController(
        model: model, appName: appName,
        refreshPermissions: { [permissions] in permissions.refresh() })
      // Done opens the main window (Design/main-app/README.md).
      let close = model.finish
      model.finish = { [weak self] in
        close()
        self?.openMainWindow()
      }
    }
    onboarding?.show()
  }

  // MARK: - Menu

  private func makeMenu() -> NSMenu {
    let warnings = HotkeyRole.allCases.compactMap { role in
      hotkeys.problems[role].map { role.warning($0) }
    }
    let menu = StatusMenu.make(appName: appName, warnings: warnings)
    menu.delegate = self
    return menu
  }

  /// Refilled on every opening, so shortcut problems found since show up.
  func menuNeedsUpdate(_ menu: NSMenu) {
    let fresh = makeMenu()
    let items = fresh.items
    fresh.removeAllItems()
    menu.removeAllItems()
    items.forEach(menu.addItem)
  }

  @objc func showAbout(_ sender: Any?) {
    NSApp.orderFrontStandardAboutPanel(sender)
    NSApp.activateFromFrontApp()
  }

  @objc func showShortcutSettings(_ sender: Any?) {
    openMainWindow(settings: .shortcuts)
  }

  /// The status menu's and the Window menu's 「打开 Dict」.
  @objc func showMainWindow(_ sender: Any?) {
    openMainWindow()
  }

  /// The status menu's and the app menu's 「设置…」, ⌘,.
  @objc func showSettings(_ sender: Any?) {
    openMainWindow(settings: .general)
  }

  @objc func checkForUpdates(_ sender: Any?) {
    updater?.checkForUpdates()
  }

  /// 「检查更新…」 is dimmed when this build has no updater or Sparkle is busy.
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    guard menuItem.action == #selector(checkForUpdates(_:)) else { return true }
    return updater?.canCheckForUpdates ?? false
  }
}

/// What opening Dict again shows.
enum ReopenTarget: Equatable {
  case onboarding, mainWindow

  init(onboardingCompleted: Bool) {
    self = onboardingCompleted ? .mainWindow : .onboarding
  }
}

/// How the process was started.
enum LaunchMode: Equatable {
  /// The unit test host.
  case unitTests
  /// The `--e2e` debug entry point.
  case endToEnd
  /// A normal launch; `--no-onboarding` keeps the first-run window closed, for scripts that
  /// launch the app in the background.
  case normal(showsOnboarding: Bool)

  static var current: LaunchMode {
    detect(
      environment: ProcessInfo.processInfo.environment, arguments: CommandLine.arguments)
  }

  static func detect(environment: [String: String], arguments: [String]) -> LaunchMode {
    if environment["XCTestConfigurationFilePath"] != nil { return .unitTests }
    if arguments.contains("--e2e") { return .endToEnd }
    return .normal(showsOnboarding: !arguments.contains("--no-onboarding"))
  }
}
