// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import Carbon

// MARK: - Menu bar Copy item (architecture 3.6, step 2)

/// Finds the menu item whose key equivalent is plain ⌘C, independent of the UI language.
/// Searches the menu bar, its menus and their items. Accessibility queue only.
func findCopyMenuItem(app: AXUIElement) -> AXUIElement? {
  guard let bar = AX.element(app, kAXMenuBarAttribute).1 else { return nil }
  func search(_ element: AXUIElement, depth: Int) -> AXUIElement? {
    guard depth < 4 else { return nil }
    for child in AX.children(element) {
      if AX.string(child, kAXMenuItemCmdCharAttribute).1 == "C",
        (AX.int(child, kAXMenuItemCmdModifiersAttribute) ?? 0) == 0
      {
        return child
      }
      if let hit = search(child, depth: depth + 1) { return hit }
    }
    return nil
  }
  return search(bar, depth: 0)
}

/// The Copy item's state; nil when the element is no longer valid. Accessibility queue only.
func copyMenuItemState(_ item: AXUIElement) -> MenuCopyState? {
  let (error, value) = AX.value(item, kAXEnabledAttribute)
  guard error == .success, let enabled = (value as? NSNumber)?.boolValue else { return nil }
  return enabled ? .enabled : .disabled
}

// MARK: - Directed ⌘C (architecture 3.6, step 3)

/// The ANSI C key, used when the current layout has no key that types "c".
let ansiCKeyCode = UInt16(kVK_ANSI_C)

/// The virtual key code whose key types `character`, searched over all 128 key codes.
func keyCode(typing character: String, translate: (UInt16) -> String?) -> UInt16 {
  (0..<128).first { translate(UInt16($0)) == character }.map(UInt16.init) ?? ansiCKeyCode
}

/// What a key types with ⌘ held, in the current keyboard layout. Main thread only (TIS).
@MainActor
func commandKeyTranslator() -> (UInt16) -> String? {
  guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
    let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
  else { return { _ in nil } }
  let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
  let keyboardType = UInt32(LMGetKbdType())
  // ⌘ in the Carbon modifier byte: layouts like "Dvorak – QWERTY ⌘" remap keys under ⌘.
  let modifiers = UInt32((cmdKey >> 8) & 0xFF)
  return { code in
    data.withUnsafeBytes { buffer -> String? in
      guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
        return nil
      }
      var deadKeys: UInt32 = 0
      var length = 0
      var chars = [UniChar](repeating: 0, count: 4)
      let status = UCKeyTranslate(
        layout, code, UInt16(kUCKeyActionDown), modifiers, keyboardType,
        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
      guard status == noErr, length > 0 else { return nil }
      return String(utf16CodeUnits: chars, count: length).lowercased()
    }
  }
}

/// Posts ⌘C to one process. A private event source and forced flags keep the user's held
/// modifiers out; posting to the pid is the only delivery that works while our panel is key.
@MainActor
func postCopyKey(to pid: pid_t) {
  let code = keyCode(typing: "c", translate: commandKeyTranslator())
  let source = CGEventSource(stateID: .privateState)
  for down in [true, false] {
    guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
    else { continue }
    event.flags = .maskCommand
    event.postToPid(pid)
  }
}

// MARK: - Secure input (architecture 3.8)

struct SecureInputState: Equatable, Sendable {
  let enabled: Bool
  let holderPID: pid_t?
}

/// Keys are never posted into the app that holds secure input. When the holder is unknown,
/// only terminals (where secure keyboard entry lives) are treated as the holder.
func blocksKeyPosting(_ state: SecureInputState, targetPID: pid_t, kind: AppKind) -> Bool {
  guard state.enabled else { return false }
  guard let holder = state.holderPID else { return kind == .terminal }
  return holder == targetPID
}

/// Reads secure input from the session dictionary; `kCGSSessionSecureInputPID` was measured
/// to be readable there through the public `CGSessionCopyCurrentDictionary`.
func currentSecureInput() -> SecureInputState {
  let session = CGSessionCopyCurrentDictionary() as? [String: Any]
  let pid = (session?["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value
  return SecureInputState(
    enabled: IsSecureEventInputEnabled(), holderPID: pid.flatMap { $0 > 0 ? $0 : nil })
}

@MainActor
func appName(pid: pid_t) -> String? {
  NSRunningApplication(processIdentifier: pid)?.localizedName
}
