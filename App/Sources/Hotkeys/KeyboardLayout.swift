// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import Foundation

/// A keyboard layout's key map, copied out of Text Input Sources so that translating keys
/// does not touch TIS again. TIS lookups must run on the main thread (architecture 2.3).
struct KeyboardLayout: Sendable {
  let id: String
  let name: String
  /// The `uchr` resource.
  private let keyMap: Data

  /// The layout keys are typed with now. For an input method such as Pinyin this is the
  /// layout it types through, for example ABC.
  @MainActor static func current() -> KeyboardLayout? {
    TISCopyCurrentKeyboardLayoutInputSource().flatMap { KeyboardLayout($0.takeRetainedValue()) }
  }

  /// Every enabled keyboard layout, plus the current one in case only an input method is
  /// enabled.
  @MainActor static func enabled() -> [KeyboardLayout] {
    var layouts = sources(matching: [:], includeAllInstalled: false)
    if let current = current(), !layouts.contains(where: { $0.id == current.id }) {
      layouts.append(current)
    }
    return layouts
  }

  /// A layout that ships with macOS, enabled or not.
  @MainActor static func installed(id: String) -> KeyboardLayout? {
    sources(matching: [kTISPropertyInputSourceID: id], includeAllInstalled: true).first
  }

  @MainActor private static func sources(
    matching properties: [CFString: Any], includeAllInstalled: Bool
  ) -> [KeyboardLayout] {
    var filter = properties
    filter[kTISPropertyInputSourceType] = kTISTypeKeyboardLayout
    let list =
      TISCreateInputSourceList(filter as CFDictionary, includeAllInstalled)?
      .takeRetainedValue() as? [TISInputSource]
    return (list ?? []).compactMap(KeyboardLayout.init)
  }

  private init?(_ source: TISInputSource) {
    guard let id: CFString = Self.property(source, kTISPropertyInputSourceID),
      let name: CFString = Self.property(source, kTISPropertyLocalizedName),
      let keyMap: CFData = Self.property(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    self.id = id as String
    self.name = name as String
    self.keyMap = keyMap as Data
  }

  private static func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
    guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? T
  }

  /// What pressing the key with these modifiers types, or nil when it types nothing.
  func output(keyCode: UInt16, modifiers: KeyCombo.Modifiers) -> KeyOutput? {
    let result = translate(keyCode: keyCode, modifiers: modifiers, allowDeadKeys: true)
    if result.deadKeyState != 0 && result.text.isEmpty { return .deadKey }
    return result.text.isEmpty ? nil : .text(result.text)
  }

  /// The character printed on the key: what it types without modifiers, with dead keys
  /// resolved to their own character.
  func character(keyCode: UInt16) -> String? {
    let text = translate(keyCode: keyCode, modifiers: [], allowDeadKeys: false).text
    return text.isEmpty ? nil : text
  }

  private func translate(
    keyCode: UInt16, modifiers: KeyCombo.Modifiers, allowDeadKeys: Bool
  ) -> (text: String, deadKeyState: UInt32) {
    keyMap.withUnsafeBytes { bytes in
      guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
        return ("", 0)
      }
      var deadKeyState: UInt32 = 0
      var length = 0
      var chars = [UniChar](repeating: 0, count: 8)
      let status = UCKeyTranslate(
        layout, keyCode, UInt16(kUCKeyActionDown), (modifiers.carbon >> 8) & 0xFF,
        UInt32(LMGetKbdType()),
        allowDeadKeys ? 0 : OptionBits(kUCKeyTranslateNoDeadKeysMask),
        &deadKeyState, chars.count, &length, &chars)
      guard status == noErr else { return ("", 0) }
      return (String(utf16CodeUnits: chars, count: length), deadKeyState)
    }
  }
}
