// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import Foundation
import Observation

/// Owns the "read" and "write" global shortcuts: validation, registration with rollback,
/// persistence and re-checking when keyboard input sources change (architecture 10.1).
///
/// Call `start()` once at launch; `onPress` receives the role of each press.
@MainActor
@Observable
final class HotkeyCenter {
  /// The saved combinations, including ones that failed to register.
  private(set) var combos: [HotkeyRole: KeyCombo]
  /// Saved combinations that are not registered or now clash with an enabled layout.
  /// The status menu shows these.
  private(set) var problems: [HotkeyRole: HotkeyProblem] = [:]
  /// Bumped when input sources change, so key names are redrawn for the new layout.
  private(set) var layoutRevision = 0

  /// While paused (when recording a new combination) no shortcut is registered, so the
  /// recorder sees every key press.
  var isPaused = false {
    didSet {
      guard isPaused != oldValue, isStarted else { return }
      if isPaused { unregisterAll() } else { registerAll() }
    }
  }

  @ObservationIgnored var onPress: (@MainActor (HotkeyRole) -> Void)?
  @ObservationIgnored private(set) var registrations: [HotkeyRole: CarbonHotkey] = [:]
  @ObservationIgnored private let store: HotkeyStore
  @ObservationIgnored private var observers: [any NSObjectProtocol] = []
  @ObservationIgnored private var isStarted = false

  init(defaults: UserDefaults = .standard) {
    store = HotkeyStore(defaults: defaults)
    combos = store.load()
  }

  /// Registers the saved combinations and starts watching input sources.
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

  /// Why `combo` cannot be used for `role`, checked against the enabled layouts and the
  /// system shortcuts as they are now.
  func problem(for combo: KeyCombo, role: HotkeyRole) -> HotkeyProblem? {
    let outputs = KeyboardLayout.enabled().compactMap { layout in
      layout.output(keyCode: combo.keyCode, modifiers: combo.modifiers).map {
        LayoutOutput(layoutName: layout.name, output: $0)
      }
    }
    return HotkeyRules.problem(
      for: combo, role: role, assigned: combos, reserved: SystemShortcuts.reserved(),
      outputs: outputs)
  }

  /// Validates, swaps the registration and saves. On failure the previous combination
  /// stays registered and saved, and the problem is returned.
  func assign(_ combo: KeyCombo, to role: HotkeyRole) -> HotkeyProblem? {
    if let problem = problem(for: combo, role: role) { return problem }
    let previous = registrations.removeValue(forKey: role)
    previous?.unregister()
    do {
      registrations[role] = try register(combo, for: role)
    } catch {
      Log.ui.error(
        "Hotkey registration failed for \(role.rawValue, privacy: .public): \(error.status, privacy: .public)"
      )
      if previous != nil, let old = combos[role] {
        registrations[role] = try? register(old, for: role)
      }
      return .registrationFailed(error.status)
    }
    combos[role] = combo
    problems[role] = nil
    store.save(combos)
    Log.ui.info("Hotkey set for \(role.rawValue, privacy: .public)")
    return nil
  }

  func clear(_ role: HotkeyRole) {
    registrations.removeValue(forKey: role)?.unregister()
    combos[role] = nil
    problems[role] = nil
    store.save(combos)
  }

  /// The combination as printed on the keys of the current layout, for example "⌃⌥D".
  func displayString(_ combo: KeyCombo) -> String {
    _ = layoutRevision  // Redraw when the layout changes.
    let typed = KeyboardLayout.current()?.character(keyCode: combo.keyCode)
    return HotkeyRules.displayString(
      combo, keyName: HotkeyRules.keyName(keyCode: combo.keyCode, typed: typed))
  }

  private func register(_ combo: KeyCombo, for role: HotkeyRole) throws(HotkeyRegistrationError)
    -> CarbonHotkey
  {
    try CarbonHotkey.register(combo) { [weak self] in self?.onPress?(role) }
  }

  private func registerAll() {
    guard !isPaused else { return }
    for (role, combo) in combos where registrations[role] == nil {
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
    recheckLayouts()
  }

  private func unregisterAll() {
    registrations.values.forEach { $0.unregister() }
    registrations = [:]
  }

  private func inputSourcesChanged() {
    layoutRevision += 1
    recheckLayouts()
  }

  /// Flags registered combinations that a newly enabled layout would type with; they stay
  /// registered so the user keeps a working shortcut while they pick another.
  private func recheckLayouts() {
    for (role, combo) in combos where registrations[role] != nil {
      problems[role] = problem(for: combo, role: role)
    }
  }
}
