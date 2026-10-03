// SPDX-License-Identifier: GPL-3.0-or-later

import ApplicationServices
import Foundation

/// The one serial queue every accessibility call runs on (architecture 2.3).
/// Callers await the result, so the main thread is never blocked by an inter-process message.
final class AXQueue: Sendable {
  private let queue = DispatchQueue(label: "au.ibra.dict.accessibility", qos: .userInitiated)

  func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
      queue.async { continuation.resume(returning: work()) }
    }
  }

  /// Blocks the caller; only for the quit path, where there is no later.
  func runAndWait<T: Sendable>(_ work: @Sendable () -> T) -> T {
    queue.sync(execute: work)
  }
}

/// Typed wrappers over the accessibility C API. Call only on `AXQueue`.
/// Every element handed out gets the per-message timeout, because the timeout is per element.
enum AX {
  static let messageTimeout: Float = 0.1

  static func application(_ pid: pid_t) -> AXUIElement {
    withTimeout(AXUIElementCreateApplication(pid))
  }

  static func withTimeout(_ element: AXUIElement) -> AXUIElement {
    AXUIElementSetMessagingTimeout(element, messageTimeout)
    return element
  }

  static func value(_ element: AXUIElement, _ attribute: String) -> (AXError, CFTypeRef?) {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    return (error, value)
  }

  static func value(
    _ element: AXUIElement, _ attribute: String, parameter: CFTypeRef
  ) -> (AXError, CFTypeRef?) {
    var value: CFTypeRef?
    let error = AXUIElementCopyParameterizedAttributeValue(
      element, attribute as CFString, parameter, &value)
    return (error, value)
  }

  static func element(_ element: AXUIElement, _ attribute: String) -> (AXError, AXUIElement?) {
    let (error, value) = value(element, attribute)
    return (error, asElement(value).map(withTimeout))
  }

  static func string(_ element: AXUIElement, _ attribute: String) -> (AXError, String?) {
    let (error, value) = value(element, attribute)
    return (error, value as? String)
  }

  static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
    let (_, value) = value(element, attribute)
    return (value as? NSNumber)?.boolValue
  }

  static func int(_ element: AXUIElement, _ attribute: String) -> Int? {
    let (_, value) = value(element, attribute)
    return (value as? NSNumber)?.intValue
  }

  static func children(_ element: AXUIElement) -> [AXUIElement] {
    let (_, value) = value(element, kAXChildrenAttribute)
    guard let array = value as? [CFTypeRef] else { return [] }
    return array.compactMap(asElement).map(withTimeout)
  }

  static func range(_ element: AXUIElement) -> CFRange? {
    let (_, value) = value(element, kAXSelectedTextRangeAttribute)
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var range = CFRange()
    return AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range)
      ? range : nil
  }

  static func rect(_ value: CFTypeRef?) -> CGRect? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var rect = CGRect.zero
    return AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgRect, &rect) ? rect : nil
  }

  static func rangeValue(_ range: CFRange) -> AXValue? {
    var range = range
    return AXValueCreate(.cfRange, &range)
  }

  static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError {
    AXUIElementSetAttributeValue(element, attribute as CFString, value)
  }

  static func press(_ element: AXUIElement) -> AXError {
    AXUIElementPerformAction(element, kAXPressAction as CFString)
  }

  /// A checked downcast: `as? AXUIElement` always succeeds for CF types.
  static func asElement(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
  }

  static func asMarkerRange(_ value: CFTypeRef?) -> AXTextMarkerRange? {
    guard let value, CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() else { return nil }
    return unsafeDowncast(value, to: AXTextMarkerRange.self)
  }
}
