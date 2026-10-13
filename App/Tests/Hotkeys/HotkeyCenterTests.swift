// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import Foundation
import Testing

@testable import DictApp

/// Registers real Carbon hotkeys on obscure combinations (⌃⌥⌘ with F16–F19) and always
/// unregisters them. Serialized because hotkeys are process-wide.
@MainActor
@Suite(.serialized)
final class HotkeyCenterTests {
  private let suiteName = "HotkeyCenterTests.\(UUID().uuidString)"
  private let defaults: UserDefaults
  private var centers: [HotkeyCenter] = []

  private static let hyper: KeyCombo.Modifiers = [.control, .option, .command]
  private let f16 = KeyCombo(keyCode: UInt16(kVK_F16), modifiers: hyper)
  private let f17 = KeyCombo(keyCode: UInt16(kVK_F17), modifiers: hyper)
  private let f18 = KeyCombo(keyCode: UInt16(kVK_F18), modifiers: hyper)
  private let f19 = KeyCombo(keyCode: UInt16(kVK_F19), modifiers: hyper)

  init() throws {
    defaults = try #require(UserDefaults(suiteName: suiteName))
  }

  deinit {
    UserDefaults.standard.removePersistentDomain(forName: suiteName)
  }

  private func makeCenter() -> HotkeyCenter {
    let center = HotkeyCenter(defaults: defaults)
    centers.append(center)
    center.start()
    return center
  }

  private func stopAll() {
    centers.forEach { $0.stop() }
  }

  /// Whether `combo` is currently held by this process: registering it again must fail.
  private func isHeld(_ combo: KeyCombo) -> Bool {
    do {
      try CarbonHotkey.register(combo) {}.unregister()
      return false
    } catch {
      return error.status == eventHotKeyExistsErr
    }
  }

  @Test func assigningRegistersAndPersists() {
    defer { stopAll() }
    let center = makeCenter()

    #expect(center.assign(.combo(f18), to: .read) == nil)
    #expect(center.shortcuts[.read] == .combo(f18))
    #expect(isHeld(f18))

    center.stop()
    #expect(!isHeld(f18))

    let restored = makeCenter()
    #expect(restored.shortcuts[.read] == .combo(f18))
    #expect(restored.problems.isEmpty)
    #expect(isHeld(f18))
  }

  @Test func changingTheComboReleasesTheOldOne() {
    defer { stopAll() }
    let center = makeCenter()

    #expect(center.assign(.combo(f18), to: .write) == nil)
    #expect(center.assign(.combo(f19), to: .write) == nil)

    #expect(!isHeld(f18))
    #expect(isHeld(f19))
  }

  @Test func theTwoRolesCannotShareACombo() {
    defer { stopAll() }
    let center = makeCenter()

    #expect(center.assign(.combo(f18), to: .read) == nil)
    #expect(center.assign(.combo(f18), to: .write) == .usedBy(.read))
    #expect(center.shortcuts[.write] == nil)
  }

  @Test func failedRegistrationRollsBackToTheOldCombo() throws {
    defer { stopAll() }
    let center = makeCenter()
    #expect(center.assign(.combo(f16), to: .read) == nil)

    let squatter = try CarbonHotkey.register(f17) {}
    defer { squatter.unregister() }

    #expect(
      center.assign(.combo(f17), to: .read) == .registrationFailed(OSStatus(eventHotKeyExistsErr)))
    #expect(center.shortcuts[.read] == .combo(f16))
    #expect(isHeld(f16))

    let reloaded = HotkeyStore(defaults: defaults).load()
    #expect(reloaded[.read] == .combo(f16))
  }

  @Test func clearingUnregistersAndForgets() {
    defer { stopAll() }
    let center = makeCenter()
    #expect(center.assign(.combo(f18), to: .read) == nil)

    center.clear(.read)

    #expect(center.shortcuts[.read] == nil)
    #expect(!isHeld(f18))
    #expect(HotkeyStore(defaults: defaults).load().isEmpty)
  }

  @Test func pausingReleasesTheCombosUntilResumed() {
    defer { stopAll() }
    let center = makeCenter()
    #expect(center.assign(.combo(f18), to: .read) == nil)

    center.isPaused = true
    #expect(!isHeld(f18))

    center.isPaused = false
    #expect(isHeld(f18))
  }

  @Test func aComboTakenAtLaunchIsReportedNotDropped() throws {
    defer { stopAll() }
    HotkeyStore(defaults: defaults).save([.read: f18])
    let squatter = try CarbonHotkey.register(f18) {}
    defer { squatter.unregister() }

    let center = makeCenter()

    #expect(center.shortcuts[.read] == .combo(f18))
    #expect(center.problems[.read] == .registrationFailed(OSStatus(eventHotKeyExistsErr)))
  }

  /// Sends the Carbon "hotkey pressed" event straight to the app's event target, which is
  /// the path a real key press takes after the window server matches the hotkey.
  /// Real key presses are on the manual checklist.
  @Test func aHotkeyEventDispatchesTheRole() throws {
    defer { stopAll() }
    let center = makeCenter()
    var pressed: [HotkeyRole] = []
    center.onPress = { pressed.append($0) }
    #expect(center.assign(.combo(f18), to: .write) == nil)
    let id = try #require(center.registrations[.write]).id

    var event: EventRef?
    #expect(
      CreateEvent(
        nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0,
        EventAttributes(kEventAttributeNone), &event) == noErr)
    let created = try #require(event)
    defer { ReleaseEvent(created) }
    var hotKeyID = EventHotKeyID(signature: CarbonHotkey.signature, id: id)
    #expect(
      SetEventParameter(
        created, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        MemoryLayout<EventHotKeyID>.size, &hotKeyID) == noErr)

    #expect(SendEventToEventTarget(created, GetApplicationEventTarget()) == noErr)
    #expect(pressed == [.write])
  }

  @Test func theMonitorRunsOnlyWhileADoublePressIsAssigned() {
    defer { stopAll() }
    let center = makeCenter()
    #expect(center.assign(.combo(f18), to: .read) == nil)
    #expect(!center.isMonitoringDoubleTaps)

    #expect(center.assign(.doubleTap(DoubleTap(.rightCommand)), to: .write) == nil)
    #expect(center.isMonitoringDoubleTaps)
    #expect(isHeld(f18))

    center.isPaused = true
    #expect(!center.isMonitoringDoubleTaps)
    center.isPaused = false
    #expect(center.isMonitoringDoubleTaps)

    center.clear(.write)
    #expect(!center.isMonitoringDoubleTaps)
  }

  @Test func aDoublePressReplacesACombinationAndReleasesIt() {
    defer { stopAll() }
    let center = makeCenter()
    #expect(center.assign(.combo(f18), to: .read) == nil)

    #expect(center.assign(.doubleTap(DoubleTap(.leftOption)), to: .read) == nil)

    #expect(!isHeld(f18))
    #expect(center.registrations[.read] == nil)
    #expect(center.shortcuts[.read] == .doubleTap(DoubleTap(.leftOption)))
  }

  @Test func aSavedDoublePressStartsTheMonitorAtLaunch() {
    defer { stopAll() }
    HotkeyStore(defaults: defaults).save([.read: Hotkey.doubleTap(DoubleTap(.leftOption))])

    let center = makeCenter()

    #expect(center.shortcuts[.read] == .doubleTap(DoubleTap(.leftOption)))
    #expect(center.isMonitoringDoubleTaps)
    center.stop()
    #expect(!center.isMonitoringDoubleTaps)
  }

  @Test func theTwoRolesCannotShareADoublePress() {
    defer { stopAll() }
    let center = makeCenter()
    #expect(center.assign(.doubleTap(DoubleTap(.leftOption)), to: .read) == nil)
    #expect(center.assign(.doubleTap(DoubleTap(.leftOption)), to: .write) == .usedBy(.read))
    #expect(center.assign(.doubleTap(DoubleTap(.rightOption)), to: .write) == .usedBy(.read))
    #expect(center.assign(.doubleTap(DoubleTap(.rightCommand)), to: .write) == nil)
  }

  /// The monitor's output, without pressing keys: either-side ⌥ ⌥ answers both ⌥ keys,
  /// right-hand ⌘ ⌘ only the right ⌘.
  @Test func aDoublePressDispatchesItsRole() {
    defer { stopAll() }
    let center = makeCenter()
    var pressed: [HotkeyRole] = []
    center.onPress = { pressed.append($0) }
    #expect(center.assign(.doubleTap(DoubleTap(.leftOption)), to: .read) == nil)
    #expect(center.assign(.doubleTap(DoubleTap(.rightCommand)), to: .write) == nil)

    center.doubleTapped(.rightCommand)
    center.doubleTapped(.leftCommand)
    center.doubleTapped(.leftOption)
    center.doubleTapped(.rightOption)
    center.doubleTapped(.leftShift)

    #expect(pressed == [.write, .read, .read])
  }

  /// `AppDelegate` calls `accessibilityGranted()` from `PermissionMonitor.onChange`.
  @Test func grantingAccessibilityReinstallsTheMonitor() throws {
    defer { stopAll() }
    let center = makeCenter()
    center.accessibilityGranted()
    #expect(!center.isMonitoringDoubleTaps)

    #expect(center.assign(.doubleTap(DoubleTap(.leftOption)), to: .read) == nil)
    let before = try #require(center.doubleTapMonitor)

    center.accessibilityGranted()

    let after = try #require(center.doubleTapMonitor)
    #expect(after !== before)
    #expect(!before.isRunning)
    #expect(after.isRunning)
  }
}
