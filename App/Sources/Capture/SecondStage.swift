// SPDX-License-Identifier: GPL-3.0-or-later

import ApplicationServices
import DictCore
import Foundation

// MARK: - Selection bounds (architecture 3.5, step 1)

/// Rects taller than this are not a selection worth anchoring the panel to (about 5 lines).
let maxSelectionHeight: CGFloat = 5 * 36

/// Converts an accessibility rect (origin at the top left of the primary screen) to Cocoa
/// screen coordinates, or nil when it is empty, off every screen or taller than 5 lines.
/// `screens` are Cocoa frames; the first is the primary screen.
func selectionBounds(fromAccessibility rect: CGRect, screens: [CGRect]) -> CGRect? {
  guard let primary = screens.first, rect.width > 0, rect.height > 0,
    rect.height <= maxSelectionHeight
  else { return nil }
  let flipped = CGRect(
    x: rect.minX, y: primary.maxY - rect.maxY, width: rect.width, height: rect.height)
  return screens.contains { $0.intersects(flipped) } ? flipped : nil
}

/// The selection's rect in accessibility coordinates. Accessibility queue only.
func readSelectionRect(_ found: FoundSelection) -> CGRect? {
  if let range = found.range, let parameter = AX.rangeValue(range) {
    let (_, value) = AX.value(
      found.element, kAXBoundsForRangeParameterizedAttribute, parameter: parameter)
    if let rect = AX.rect(value) { return rect }
  }
  if let markerRange = found.markerRange {
    let (_, value) = AX.value(found.element, "AXBoundsForTextMarkerRange", parameter: markerRange)
    return AX.rect(value)
  }
  return nil
}

// MARK: - Context sentence (architecture 3.5, step 2)

/// Characters read on each side of the selection in native text controls.
let contextRadius = 500

/// The window of `radius` UTF-16 units on each side of `selection`, clamped to `total`.
func contextWindow(selection: NSRange, total: Int, radius: Int) -> NSRange {
  let start = max(0, selection.location - radius)
  let end = min(total, NSMaxRange(selection) + radius)
  return NSRange(location: start, length: max(0, end - start))
}

/// The sentence of `text` containing `selection` (UTF-16 offsets), through DictCore's
/// `sentence(containing:in:)`; nil when the selection is out of range.
func contextSentence(in text: String, selection: NSRange) -> ContextSentence? {
  guard let term = Range(selection, in: text) else { return nil }
  return sentence(containing: term, in: text)
}

/// Reads the context sentence of a found selection. Accessibility queue only.
func readContext(_ found: FoundSelection, kind: AppKind) -> ContextSentence? {
  // Chromium's values and ranges disagree about paragraph breaks: markers only there.
  let usesMarkers = kind == .chromium || kind == .electron
  if !usesMarkers, let range = found.range, let context = nativeContext(found.element, range) {
    return context
  }
  let marker =
    found.markerRange.map { _ in found }
    ?? selectedMarkerText(found.element)
    ?? webAreaAncestor(of: found.element).flatMap(selectedMarkerText)
  guard let marker, let markerRange = marker.markerRange else { return nil }
  return markerContext(marker.element, markerRange, length: found.text.utf16.count)
}

/// Native text controls: a window around the range through `AXStringForRange`.
private func nativeContext(_ element: AXUIElement, _ range: CFRange) -> ContextSentence? {
  guard let total = AX.int(element, AXNames.numberOfCharacters) else { return nil }
  let selection = NSRange(location: range.location, length: range.length)
  let window = contextWindow(selection: selection, total: total, radius: contextRadius)
  guard
    let parameter = AX.rangeValue(CFRange(location: window.location, length: window.length)),
    let text = AX.value(element, kAXStringForRangeParameterizedAttribute, parameter: parameter).1
      as? String
  else { return nil }
  let local = NSRange(location: selection.location - window.location, length: selection.length)
  return contextSentence(in: text, selection: local)
}

/// Web content: the paragraph from the start marker's paragraph start to the end marker's
/// paragraph end, then the selection's offset in it. The only method that was right in both
/// Chrome and Safari, inline markup included.
private func markerContext(
  _ element: AXUIElement, _ markerRange: AXTextMarkerRange, length: Int
) -> ContextSentence? {
  let start = AXTextMarkerRangeCopyStartMarker(markerRange)
  let end = AXTextMarkerRangeCopyEndMarker(markerRange)
  guard
    let paragraphStart = AX.value(
      element, "AXPreviousParagraphStartTextMarkerForTextMarker", parameter: start
    ).1,
    let paragraphEnd = AX.value(
      element, "AXNextParagraphEndTextMarkerForTextMarker", parameter: end
    ).1,
    let paragraph = markerString(element, from: paragraphStart, to: paragraphEnd)
  else { return nil }
  let before = markerString(element, from: paragraphStart, to: start) ?? ""
  return contextSentence(
    in: paragraph, selection: NSRange(location: before.utf16.count, length: length))
}

private func markerString(_ element: AXUIElement, from: CFTypeRef, to: CFTypeRef) -> String? {
  let pair = [from, to] as CFArray
  guard
    let range = AX.value(element, "AXTextMarkerRangeForUnorderedTextMarkers", parameter: pair).1
  else { return nil }
  return AX.value(element, AXNames.stringForTextMarkerRange, parameter: range).1 as? String
}
