// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox

struct HotkeyRegistrationError: Error, Equatable {
  let status: OSStatus
}

/// One registered Carbon hotkey (`RegisterEventHotKey`). Registration needs no permission,
/// and the key press is consumed: the frontmost app does not see it (architecture 10.1).
///
/// A single application event handler serves every hotkey and finds the action by id, so
/// no pointer to a Swift object is handed to Carbon.
@MainActor
final class CarbonHotkey {
  nonisolated static let signature: OSType = 0x4449_4354  // 'DICT'

  let id: UInt32
  private var ref: EventHotKeyRef?

  private static var actions: [UInt32: @MainActor () -> Void] = [:]
  private static var nextID: UInt32 = 1
  private static var handlerInstalled = false

  private init(id: UInt32, ref: EventHotKeyRef) {
    self.id = id
    self.ref = ref
  }

  static func register(
    _ combo: KeyCombo, action: @escaping @MainActor () -> Void
  ) throws(HotkeyRegistrationError) -> CarbonHotkey {
    try installHandlerIfNeeded()
    let id = nextID
    nextID += 1
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      UInt32(combo.keyCode), combo.modifiers.carbon, EventHotKeyID(signature: signature, id: id),
      GetApplicationEventTarget(), 0, &ref)
    guard status == noErr, let ref else {
      throw HotkeyRegistrationError(status: status == noErr ? OSStatus(paramErr) : status)
    }
    actions[id] = action
    return CarbonHotkey(id: id, ref: ref)
  }

  /// Safe to call more than once.
  func unregister() {
    guard let ref else { return }
    UnregisterEventHotKey(ref)
    self.ref = nil
    Self.actions[id] = nil
  }

  private static func installHandlerIfNeeded() throws(HotkeyRegistrationError) {
    guard !handlerInstalled else { return }
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let status = InstallEventHandler(
      GetApplicationEventTarget(), handleHotKeyEvent, 1, &spec, nil, nil)
    guard status == noErr else { throw HotkeyRegistrationError(status: status) }
    handlerInstalled = true
  }

  fileprivate static func fire(id: UInt32) -> Bool {
    guard let action = actions[id] else { return false }
    action()
    return true
  }
}

/// Carbon delivers hotkey events on the main thread's event loop.
private func handleHotKeyEvent(
  _ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
  var hotKeyID = EventHotKeyID()
  let status = GetEventParameter(
    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
  guard status == noErr, hotKeyID.signature == CarbonHotkey.signature else {
    return OSStatus(eventNotHandledErr)
  }
  let handled = MainActor.assumeIsolated { CarbonHotkey.fire(id: hotKeyID.id) }
  return handled ? noErr : OSStatus(eventNotHandledErr)
}
