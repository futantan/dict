// SPDX-License-Identifier: GPL-3.0-or-later
//
// Accessibility helpers for the driver's own checks (fixture self-test, matrix set-up).
// The driver runs from the terminal and borrows the terminal's Accessibility grant.

import AppKit
import ApplicationServices

@MainActor
enum AX {
  static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
      return nil
    }
    return value
  }

  static func element(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
  }

  static func string(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
  }

  static func children(_ element: AXUIElement) -> [AXUIElement] {
    (attribute(element, kAXChildrenAttribute) as? [AnyObject] ?? []).compactMap { AX.element($0) }
  }

  static func app(_ pid: pid_t) -> AXUIElement { AXUIElementCreateApplication(pid) }

  static func focusedElement(_ pid: pid_t) -> AXUIElement? {
    element(attribute(app(pid), kAXFocusedUIElementAttribute))
  }

  /// `AXSelectedText`, or for web text that only answers through text markers,
  /// `AXSelectedTextMarkerRange` → `AXStringForTextMarkerRange`.
  static func selectedText(_ element: AXUIElement) -> String? {
    if let text = string(element, kAXSelectedTextAttribute), !text.isEmpty { return text }
    guard let range = attribute(element, "AXSelectedTextMarkerRange") else { return nil }
    var value: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        element, "AXStringForTextMarkerRange" as CFString, range, &value) == .success
    else { return nil }
    return value as? String
  }

  /// The identifier tests address a control by: `AXIdentifier`, or `AXDOMIdentifier` on web
  /// content.
  static func identifier(_ element: AXUIElement) -> String? {
    string(element, kAXIdentifierAttribute) ?? string(element, "AXDOMIdentifier")
  }

  /// The first menu bar item whose ⌘-only key equivalent is `key`, such as "C" for Copy.
  static func menuItem(_ pid: pid_t, key: String) -> AXUIElement? {
    guard let menuBar = element(attribute(app(pid), kAXMenuBarAttribute)) else { return nil }
    for top in children(menuBar) {
      for menu in children(top) {
        for item in children(menu)
        where string(item, kAXMenuItemCmdCharAttribute) == key
          && (attribute(item, kAXMenuItemCmdModifiersAttribute) as? Int ?? -1) == 0
        {
          return item
        }
      }
    }
    return nil
  }

  static func isEnabled(_ element: AXUIElement) -> Bool {
    attribute(element, kAXEnabledAttribute) as? Bool ?? false
  }

  @discardableResult
  static func press(_ element: AXUIElement) -> AXError {
    AXUIElementPerformAction(element, kAXPressAction as CFString)
  }

  static func set(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> AXError {
    AXUIElementSetAttributeValue(element, name as CFString, value)
  }

  static func windows(_ pid: pid_t) -> [AXUIElement] {
    (attribute(app(pid), kAXWindowsAttribute) as? [AnyObject] ?? []).compactMap { AX.element($0) }
  }

  static func title(_ element: AXUIElement) -> String? { string(element, kAXTitleAttribute) }

  static func focusedWindowTitle(_ pid: pid_t) -> String? {
    element(attribute(app(pid), kAXFocusedWindowAttribute)).flatMap(title)
  }
}
