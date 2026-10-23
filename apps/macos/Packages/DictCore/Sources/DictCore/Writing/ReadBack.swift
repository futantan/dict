// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What reading the field back after a replacement shows (architecture 4.5).
public enum ReadBack: Sendable, Equatable {
  case unchanged
  /// The result occurs once more and the original once less.
  case confirmed
  /// The result occurs twice more: the write landed and so did a paste.
  case duplicated
  case changedUnexpectedly
}

/// Judges a replacement by counting occurrences, not by offsets: Chromium's contenteditable
/// value and range offsets disagree. All four texts are normalized the same way first.
public func replacementConfirmed(
  before: String, after: String, original: String, result: String
) -> ReadBack {
  let before = normalizedForReadBack(before)
  let after = normalizedForReadBack(after)
  if after == before { return .unchanged }
  let original = normalizedForReadBack(original)
  let result = normalizedForReadBack(result)
  let addedResults = count(result, in: after) - count(result, in: before)
  let removedOriginals = count(original, in: before) - count(original, in: after)
  if addedResults == 1 && removedOriginals == 1 { return .confirmed }
  if addedResults == 2 { return .duplicated }
  return .changedUnexpectedly
}

/// NFC; `\r\n` and `\r` as `\n`; runs of other whitespace as one space; no zero-width
/// characters or U+FFFC.
func normalizedForReadBack(_ text: String) -> String {
  let invisible: Set<Unicode.Scalar> = [
    "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}", "\u{FFFC}",
  ]
  let unified = text.precomposedStringWithCanonicalMapping
    .replacingOccurrences(of: "\r\n", with: "\n")
    .replacingOccurrences(of: "\r", with: "\n")
  var scalars = String.UnicodeScalarView()
  var inSpace = false
  for scalar in unified.unicodeScalars where !invisible.contains(scalar) {
    if scalar != "\n" && scalar.properties.isWhitespace {
      if !inSpace { scalars.append(" ") }
      inSpace = true
    } else {
      scalars.append(scalar)
      inSpace = false
    }
  }
  return String(scalars)
}

/// Non-overlapping occurrences of a non-empty `needle`.
private func count(_ needle: String, in text: String) -> Int {
  guard !needle.isEmpty else { return 0 }
  return text.ranges(of: needle).count
}
