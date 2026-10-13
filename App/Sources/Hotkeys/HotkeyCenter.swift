// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import Foundation
import Observation

/// Owns the "read" and "write" global shortcuts: validation, registration with rollback,
/// persistence, and redrawing key names when keyboard input sources change (architecture
/// 10.1). Combinations go through Carbon; double presses of a modifier through an event
/// monitor, which runs only while some role has one.
///
/// Call `start()` once at launch; `onPress` receives the role of each press.
@MainActor
@Observable
final class HotkeyCenter {
  /// The saved shortcuts, combinations and double presses alike, including ones that
  /// failed to register.
  private(set) var combos: [HotkeyRole: Hotkey]
  /// Saved shortcuts that are not registered or now clash with a system shortcut.
  /// The status menu shows these.
  private(set) var problems: [HotkeyRole: HotkeyProblem] = [:]
  /// Bumped when input sources change, so key names are redrawn for the new layout.
  private(set) var layoutRevision = 0

  /// While paused (when recording a new shortcut) nothing is registered or monitored, so
  /// the recorder sees every key press.
  var isPaused = false {
    didSet {
      guard isPaused != oldValue, isStarted else { return }
      if isPaused { unregisterAll() } else { registerAll() }
    }
  }

  @ObservationIgnored var onPress: (@MainActor (HotkeyRole) -> Void)?
  @ObservationIgnored private(set) var registrations: [HotkeyRole: CarbonHotkey] = [:]
  @ObservationIgnored private var doubleTapMonitor: DoubleTapMonitor?
  @ObservationIgnored private let store: HotkeyStore
  @ObservationIgnored private var observers: [any NSObjectProtocol] = []
  @ObservationIgnored private var isStarted = false

  init(defaults: UserDefaults = .standard) {
    store = HotkeyStore(defaults: defaults)
    combos = store.load()
  }

  /// Whether the double-press monitor is installed.
  var isMonitoringDoubleTaps: Bool { doubleTapMonitor != nil }

  /// Registers the saved shortcuts and starts watching input sources.
  func start() {
    guard !isStarted else { return }
    isStarted = true
    combos = store.load()
    registerAll()
    let center = DistributedNotificationCenter.default()
    observers = [
      kTISNotifySelectedKeyboardInputSourceChanged, kTISNotifyEnabledKeyboardInputSourcesChanged,
    ]
    .map { name in
      center.addObserver(forName: Notification.Name(name as String), object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated { self?.inputSourcesChanged() }
      }
    }
  }

  /// Unregisters everything and stops watching input sources.
  func stop() {
    guard isStarted else { return }
    isStarted = false
    unregisterAll()
    observers.forEach(DistributedNotificationCenter.default().removeObserver)
    observers = []
  }

  /// Reinstalls the double-press monitor. Call after Accessibility is granted, in case a
  /// monitor installed without it never receives other apps' events.
  func accessibilityGranted() {
    guard doubleTapMonitor != nil else { return }
    doubleTapMonitor?.stop()
    doubleTapMonitor = nil
    updateDoubleTapMonitor()
  }

  /// Why `hotkey` cannot be used for `role`, checked against the system shortcuts as they
  /// are now.
  func problem(for hotkey: Hotkey, role: HotkeyRole) -> HotkeyProblem? {
    HotkeyRules.problem(
      for: hotkey, role: role, assigned: combos, reserved: SystemShortcuts.reserved())
  }

  /// Validates, swaps the registration and saves. On failure the previous shortcut stays
  /// registered and saved, and the problem is returned.
  func assign(_ hotkey: Hotkey, to role: HotkeyRole) -> HotkeyProblem? {
    if let problem = problem(for: hotkey, role: role) { return problem }
    let previous = registrations.removeValue(forKey: role)
    previous?.unregister()
    if case .combo(let combo) = hotkey {
      do {
        registrations[role] = try register(combo, for: role)
      } catch {
        Log.ui.error(
          "Hotkey registration failed for \(role.rawValue, privacy: .public): \(error.status, privacy: .public)"
        )
        if previous != nil, case .combo(let old) = combos[role] {
          registrations[role] = try? register(old, for: role)
        }
        return .registrationFailed(error.status)
      }
    }
    combos[role] = hotkey
    problems[role] = nil
    store.save(combos)
    updateDoubleTapMonitor()
    Log.ui.info("Hotkey set for \(role.rawValue, privacy: .public)")
    return nil
  }

  func clear(_ role: HotkeyRole) {
    registrations.removeValue(forKey: role)?.unregister()
    combos[role] = nil
    problems[role] = nil
    store.save(combos)
    updateDoubleTapMonitor()
  }

  /// The shortcut as printed on the keys of the current layout, for example "⌃⌥D" or
  /// "⌥ ⌥".
  func displayString(_ hotkey: Hotkey) -> String {
    switch hotkey {
    case .combo(let combo):
      _ = layoutRevision  // Redraw when the layout changes.
      let typed = KeyboardLayout.current()?.character(keyCode: combo.keyCode)
      return HotkeyRules.displayString(
        combo, keyName: HotkeyRules.keyName(keyCode: combo.keyCode, typed: typed))
    case .doubleTap(let key):
      return HotkeyRules.displayString(doubleTap: key)
    }
  }

  /// A double press seen by the monitor.
  func doubleTapped(_ key: ModifierKey) {
    guard let role = combos.first(where: { $0.value == .doubleTap(key) })?.key else { return }
    onPress?(role)
  }

  private func register(_ combo: KeyCombo, for role: HotkeyRole) throws(HotkeyRegistrationError)
    -> CarbonHotkey
  {
    try CarbonHotkey.register(combo) { [weak self] in self?.onPress?(role) }
  }

  private func registerAll() {
    guard !isPaused else { return }
    for (role, hotkey) in combos where registrations[role] == nil {
      guard case .combo(let combo) = hotkey else { continue }
      do {
        registrations[role] = try register(combo, for: role)
        problems[role] = nil
      } catch {
        Log.ui.error(
          "Hotkey registration failed for \(role.rawValue, privacy: .public): \(error.status, privacy: .public)"
        )
        problems[role] = .registrationFailed(error.status)
      }
    }
    updateDoubleTapMonitor()
    recheckRegistered()
  }

  private func unregisterAll() {
    registrations.values.forEach { $0.unregister() }
    registrations = [:]
    doubleTapMonitor?.stop()
    doubleTapMonitor = nil
  }

  /// Installs the monitor while started, not paused and some role has a double press;
  /// removes it otherwise.
  private func updateDoubleTapMonitor() {
    let wanted =
      isStarted && !isPaused
      && combos.values.contains {
        if case .doubleTap = $0 { true } else { false }
      }
    if wanted, doubleTapMonitor == nil {
      let monitor = DoubleTapMonitor { [weak self] in self?.doubleTapped($0) }
      monitor.start()
      doubleTapMonitor = monitor
    } else if !wanted, let monitor = doubleTapMonitor {
      monitor.stop()
      doubleTapMonitor = nil
    }
  }

  private func inputSourcesChanged() {
    layoutRevision += 1
  }

  /// Flags registered combinations that macOS has since reserved; they stay registered so
  /// the user keeps a working shortcut while they pick another.
  private func recheckRegistered() {
    for (role, hotkey) in combos where registrations[role] != nil {
      problems[role] = problem(for: hotkey, role: role)
    }
  }
}
