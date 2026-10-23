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

/// `paragraph` cut down to the part that is also in `value`, the focused element's text, and
/// `selection` moved into it. Electron's paragraph markers can run past the element into the
/// surrounding UI (VS Code: the tab title, U+FFFC and the Chat panel title), and the element's
/// value cannot. The selection is anchored in `value` at `valueRange` when that holds the same
/// text, else at its only occurrence; without an anchor the paragraph is returned unchanged.
/// From there the clip keeps the text before and after the selection that both strings share.
func clip(
  paragraph: String, selection: NSRange, to value: String?, valueRange: NSRange?
) -> (String, NSRange) {
  let unchanged = (paragraph, selection)
  let text = paragraph as NSString
  guard let value, NSMaxRange(selection) <= text.length else { return unchanged }
  let valueText = value as NSString
  let selected = text.substring(with: selection)
  let anchor: NSRange
  if let valueRange, NSMaxRange(valueRange) <= valueText.length,
    valueText.substring(with: valueRange) == selected
  {
    anchor = valueRange
  } else {
    let first = valueText.range(of: selected)
    guard first.location != NSNotFound else { return unchanged }
    let rest = NSRange(location: first.location + 1, length: valueText.length - first.location - 1)
    guard valueText.range(of: selected, range: rest).location == NSNotFound else {
      return unchanged
    }
    anchor = first
  }

  var before = 0
  while before < min(selection.location, anchor.location),
    text.character(at: selection.location - before - 1)
      == valueText.character(at: anchor.location - before - 1)
  {
    before += 1
  }
  var after = 0
  while NSMaxRange(selection) + after < text.length,
    NSMaxRange(anchor) + after < valueText.length,
    text.character(at: NSMaxRange(selection) + after)
      == valueText.character(at: NSMaxRange(anchor) + after)
  {
    after += 1
  }
  let kept = NSRange(
    location: selection.location - before, length: before + selection.length + after)
  return (text.substring(with: kept), NSRange(location: before, length: selection.length))
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
  guard let marker, let markerRange = marker.markerRange,
    let read = markerParagraph(
      marker.element, markerRange, length: found.text.utf16.count)
  else { return nil }
  let (paragraph, selection) = read
  // An editable element with a range (VS Code's editor, a web text field) bounds the
  // paragraph; read-only web text has no such element.
  let (clipped, local) = clip(
    paragraph: paragraph, selection: selection,
    to: found.range.flatMap { _ in fieldText(found.element) },
    valueRange: found.range.map { NSRange(location: $0.location, length: $0.length) })
  return contextSentence(in: clipped, selection: local)
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
/// paragraph end, and the selection's range in it. The only method that was right in both
/// Chrome and Safari, inline markup included.
private func markerParagraph(
  _ element: AXUIElement, _ markerRange: AXTextMarkerRange, length: Int
) -> (String, NSRange)? {
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
  return (paragraph, NSRange(location: before.utf16.count, length: length))
}

private func markerString(_ element: AXUIElement, from: CFTypeRef, to: CFTypeRef) -> String? {
  let pair = [from, to] as CFArray
  guard
    let range = AX.value(element, "AXTextMarkerRangeForUnorderedTextMarkers", parameter: pair).1
  else { return nil }
  return AX.value(element, AXNames.stringForTextMarkerRange, parameter: range).1 as? String
}
