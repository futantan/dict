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

  /// A layout that ships with macOS, enabled or not.
  @MainActor static func installed(id: String) -> KeyboardLayout? {
    var filter: [CFString: Any] = [kTISPropertyInputSourceID: id]
    filter[kTISPropertyInputSourceType] = kTISTypeKeyboardLayout
    let list =
      TISCreateInputSourceList(filter as CFDictionary, true)?
      .takeRetainedValue() as? [TISInputSource]
    return list?.first.flatMap(KeyboardLayout.init)
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

  /// The character printed on the key: what it types without modifiers, with dead keys
  /// resolved to their own character.
  func character(keyCode: UInt16) -> String? {
    keyMap.withUnsafeBytes { bytes in
      guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
        return nil
      }
      var deadKeyState: UInt32 = 0
      var length = 0
      var chars = [UniChar](repeating: 0, count: 8)
      let status = UCKeyTranslate(
        layout, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, chars.count, &length, &chars)
      guard status == noErr, length > 0 else { return nil }
      return String(utf16CodeUnits: chars, count: length)
    }
  }
}
