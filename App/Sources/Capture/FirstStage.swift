// SPDX-License-Identifier: GPL-3.0-or-later

import ApplicationServices
import Foundation

/// One read of the focused element's selection (architecture 3.4).
enum ReadAttempt<Found> {
  case found(Found)
  case secureField
  /// The element is readable but nothing is selected; `fieldText` is its whole value if small.
  case empty(fieldText: String?)
  /// `noValue`: the tree is not ready yet (Safari's first poll); worth retrying.
  case notReady(AXError)
  case failed(AXError)
}

enum FirstStageOutcome<Found> {
  case found(Found)
  case failed(CaptureFailure)
}

extension FirstStageOutcome: Equatable where Found: Equatable {}

/// Repeats `attempt` while it reports `notReady`, every `interval`, until `deadline`.
/// A retry starts only if one more attempt as long as the last still fits before the deadline.
func pollFirstStage<Found>(
  deadline: Duration, interval: Duration,
  elapsed: () -> Duration, sleep: (Duration) -> Void,
  attempt: () -> ReadAttempt<Found>
) -> FirstStageOutcome<Found> {
  while true {
    let started = elapsed()
    switch attempt() {
    case .found(let found): return .found(found)
    case .secureField: return .failed(.secureField)
    case .empty(let fieldText): return .failed(.nothingSelected(fieldText: fieldText))
    case .failed(.apiDisabled): return .failed(.noAccessibilityPermission)
    case .failed(let error): return .failed(.unreadable(axError: error.rawValue))
    case .notReady(let error):
      let now = elapsed()
      guard now + interval + (now - started) <= deadline else {
        return .failed(.unreadable(axError: error.rawValue))
      }
      sleep(interval)
    }
  }
}

/// What the first stage found, kept on the accessibility queue for the second stage.
struct FoundSelection {
  let text: String
  /// The element that answered: the focused element, or the web area holding a marker range.
  let element: AXUIElement
  /// Present when the selection was read as `kAXSelectedText` from an element with a range.
  let range: CFRange?
  /// Present when the selection was read through text markers.
  let markerRange: AXTextMarkerRange?
}

enum AXNames {
  static let secureTextField = "AXSecureTextField"
  static let webArea = "AXWebArea"
  static let selectedTextMarkerRange = "AXSelectedTextMarkerRange"
  static let stringForTextMarkerRange = "AXStringForTextMarkerRange"
  static let numberOfCharacters = "AXNumberOfCharacters"
}

/// Field text larger than this is not kept for the no-selection case.
let maxFieldTextLength = 200_000

/// One attempt at reading the selection of `app`'s focused element. Accessibility queue only.
func readSelectionAttempt(app: AXUIElement) -> ReadAttempt<FoundSelection> {
  let (focusError, focused) = AX.element(app, kAXFocusedUIElementAttribute)
  guard let focused else {
    return focusError == .noValue ? .notReady(focusError) : .failed(focusError)
  }
  if AX.string(focused, kAXSubroleAttribute).1 == AXNames.secureTextField { return .secureField }

  let isWebArea = AX.string(focused, kAXRoleAttribute).1 == AXNames.webArea
  let (selectedError, selected) = AX.string(focused, kAXSelectedTextAttribute)
  if !isWebArea, let selected, !selected.isEmpty {
    return .found(
      FoundSelection(text: selected, element: focused, range: AX.range(focused), markerRange: nil))
  }

  // Safari's read-only web text answers only through text markers.
  let marker =
    selectedMarkerText(focused) ?? webAreaAncestor(of: focused).flatMap(selectedMarkerText)
  if let marker, !marker.text.isEmpty { return .found(marker) }

  if selected != nil || marker != nil {
    return .empty(fieldText: fieldText(focused))
  }
  switch selectedError {
  case .noValue: return .notReady(selectedError)
  case .success: return .failed(.failure)
  default: return .failed(selectedError)
  }
}

/// The selection of `element` as a text-marker range and its string.
func selectedMarkerText(_ element: AXUIElement) -> FoundSelection? {
  let (_, value) = AX.value(element, AXNames.selectedTextMarkerRange)
  guard let markerRange = AX.asMarkerRange(value) else { return nil }
  let (_, text) = AX.value(element, AXNames.stringForTextMarkerRange, parameter: markerRange)
  return FoundSelection(
    text: text as? String ?? "", element: element, range: nil, markerRange: markerRange)
}

/// The nearest `AXWebArea` above `element`, at most 10 levels up.
func webAreaAncestor(of element: AXUIElement) -> AXUIElement? {
  var current = AX.element(element, kAXParentAttribute).1
  for _ in 0..<10 {
    guard let node = current else { return nil }
    if AX.string(node, kAXRoleAttribute).1 == AXNames.webArea { return node }
    current = AX.element(node, kAXParentAttribute).1
  }
  return nil
}

/// The whole value of a field with no selection, for "process the whole field" and the
/// whole-line copy check; nil when unavailable or too large.
func fieldText(_ element: AXUIElement) -> String? {
  if let count = AX.int(element, AXNames.numberOfCharacters), count > maxFieldTextLength {
    return nil
  }
  guard let value = AX.string(element, kAXValueAttribute).1,
    value.utf16.count <= maxFieldTextLength
  else { return nil }
  return value
}
