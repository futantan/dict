// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private var statusItem: NSStatusItem?
  private var appName = ProcessInfo.processInfo.processName

  private let hotkeys = HotkeyCenter()
  private let permissions = PermissionMonitor()
  private let panel = PanelController()
  private let guide = PermissionGuide()
  private let presets = (try? ProviderPreset.all()) ?? []
  private var reader: AccessibilitySelectionReader?
  private var coordinator: SessionCoordinator?
  private var onboarding: OnboardingWindowController?
  private var observers: [any NSObjectProtocol] = []

  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    #if DEBUG
      E2ERunner.startIfRequested()
    #endif
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let identity = AppIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])
    appName = identity?.name ?? appName

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(
      systemSymbolName: "character.book.closed", accessibilityDescription: appName)
    item.menu = makeMenu()
    statusItem = item

    switch LaunchMode.current {
    case .unitTests, .endToEnd:
      // The test host and the e2e runner drive their own objects; no shortcuts or windows.
      return
    case .normal(let onboarding):
      start(showingOnboarding: onboarding)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    hotkeys.stop()
    permissions.stop()
  }

  // MARK: - Wiring

  private func start(showingOnboarding: Bool) {
    // The Shortcuts pane must record into the registered center, not a copy that never runs.
    SettingsWindowController.shared.hotkeys = hotkeys

    let reader = AccessibilitySelectionReader()
    reader.start()
    self.reader = reader
    let coordinator = makeCoordinator(reader: reader)
    self.coordinator = coordinator

    panel.onDismiss = { [weak coordinator] in coordinator?.panelDismissed($0) }
    panel.onSubmit = { [weak coordinator] in coordinator?.submitted($0) }
    panel.onAction = { [weak coordinator] in coordinator?.perform($0) }
    hotkeys.onPress = { [weak coordinator] in coordinator?.hotkeyPressed($0) }
    hotkeys.start()

    permissions.onChange = { [weak self] status, granted in
      self?.coordinator?.permissionsChanged(granted: granted)
      self?.onboarding?.model.permissionsChanged(status)
    }
    permissions.start()
    observeOwnWindows()

    let model = OnboardingModel(hotkeys: hotkeys, permissions: permissions.status)
    if showingOnboarding && !model.isCompleted {
      showOnboarding(model: model)
    }
    Log.ui.info(
      "started: accessibility \(self.permissions.status.accessibility, privacy: .public), shortcuts \(self.hotkeys.combos.count, privacy: .public)"
    )
  }

  private func makeCoordinator(reader: AccessibilitySelectionReader) -> SessionCoordinator {
    let presets = presets
    let guide = guide
    return SessionCoordinator(
      reader: reader, panel: panel,
      environment: SessionCoordinator.Environment(
        makeTranslator: {
          let preferences = PreferencesStore(defaults: .standard).load()
          let model = configuredModel(
            preferences.model, presets: presets, secrets: KeychainStore.app
          ).map {
            ModelTranslator(
              model: ChatCompletionsModel(
                endpoint: $0.configuration.endpoint, rules: $0.configuration.rules,
                apiKey: $0.apiKey))
          }
          return TranslationEngine(model: model)
        },
        languagePair: { PreferencesStore(defaults: .standard).load().languagePair },
        refreshPermissions: { [permissions] in permissions.refresh() },
        permissionNotice: { guide.notice(for: $0) },
        performPermissionAction: { guide.perform($0) },
        openSettings: { SettingsWindowController.shared.show(.model) },
        openLanguageDownload: { [weak self] in self?.showOnboarding(step: .translation) },
        mouseLocation: { NSEvent.mouseLocation }))
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
          if window === self.onboarding?.window {
            self.refreshOnboardingLanguages()
          }
        }
      })
  }

  // MARK: - Onboarding

  private func showOnboarding(model: OnboardingModel? = nil, step: OnboardingStep? = nil) {
    if onboarding == nil {
      let model = model ?? OnboardingModel(hotkeys: hotkeys, permissions: permissions.status)
      model.openAccessibilitySettings = { [guide] in
        _ = guide.perform(PermissionGuide.ActionID.openSettings)
      }
      model.openSettings = { SettingsWindowController.shared.show(.model) }
      onboarding = OnboardingWindowController(model: model, appName: appName)
    }
    onboarding?.show(step)
  }

  private func refreshOnboardingLanguages() {
    guard let model = onboarding?.model else { return }
    let pair = PreferencesStore(defaults: .standard).load().languagePair
    Task { await model.refreshLanguages(pair) }
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
    SettingsWindowController.shared.show(.shortcuts)
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
