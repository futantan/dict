// SPDX-License-Identifier: GPL-3.0-or-later

/// The diff between two texts as runs (architecture 6.7): Latin-script words and numbers
/// change whole, Chinese and Japanese characters one by one, a run of whitespace is one
/// unit, and other characters stand alone. Neighbouring changes, and changes only
/// whitespace apart, merge into one run. Above 20 000 units in all, the whole text is one
/// change.
public func textDiff(_ old: String, _ new: String) -> [DiffSegment] {
  if old == new { return old.isEmpty ? [] : [.unchanged(old)] }
  let before = diffUnits(old)
  let after = diffUnits(new)
  guard before.count + after.count <= 20_000 else { return [.changed(from: old, to: new)] }

  let difference = after.difference(from: before)
  var removed = Set<Int>()
  var inserted = Set<Int>()
  for change in difference {
    switch change {
    case .remove(let offset, _, _): removed.insert(offset)
    case .insert(let offset, _, _): inserted.insert(offset)
    }
  }

  var segments: [DiffSegment] = []
  var same = ""
  var i = 0
  var j = 0
  while i < before.count || j < after.count {
    if i < before.count, j < after.count, !removed.contains(i), !inserted.contains(j) {
      same += before[i]
      i += 1
      j += 1
      continue
    }
    var from = ""
    var to = ""
    while i < before.count, removed.contains(i) {
      from += before[i]
      i += 1
    }
    while j < after.count, inserted.contains(j) {
      to += after[j]
      j += 1
    }
    if !same.isEmpty { segments.append(.unchanged(same)) }
    same = ""
    segments.append(.changed(from: from, to: to))
  }
  if !same.isEmpty { segments.append(.unchanged(same)) }
  return mergingAcrossSpaces(segments)
}

/// Joins two changes separated only by whitespace into one, so "has went" → "have gone"
/// reads as one edit rather than two.
private func mergingAcrossSpaces(_ segments: [DiffSegment]) -> [DiffSegment] {
  var merged: [DiffSegment] = []
  for segment in segments {
    if case .changed(let from, let to) = segment, merged.count >= 2,
      case .unchanged(let gap) = merged[merged.count - 1],
      gap.allSatisfy(\.isWhitespace),
      case .changed(let previousFrom, let previousTo) = merged[merged.count - 2]
    {
      merged.removeLast(2)
      merged.append(.changed(from: previousFrom + gap + from, to: previousTo + gap + to))
    } else {
      merged.append(segment)
    }
  }
  return merged
}

/// Splits text into the units `textDiff` compares.
func diffUnits(_ text: String) -> [String] {
  enum Kind { case word, space, single }
  func kind(_ character: Character) -> Kind {
    if character.isWhitespace { return .space }
    let isIdeograph = character.unicodeScalars.contains {
      $0.properties.isIdeographic || (0x3040...0x30FF).contains($0.value)
    }
    if !isIdeograph && (character.isLetter || character.isNumber) { return .word }
    return .single
  }
  var units: [String] = []
  var current = ""
  var currentKind: Kind?
  for character in text {
    let next = kind(character)
    if next != .single, next == currentKind {
      current.append(character)
      continue
    }
    if !current.isEmpty { units.append(current) }
    current = String(character)
    currentKind = next
  }
  if !current.isEmpty { units.append(current) }
  return units
}
