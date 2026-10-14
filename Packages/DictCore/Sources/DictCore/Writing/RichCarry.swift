// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The source's formatting carried onto the text the diff `segments` describe (architecture
/// 4.7), so a replacement keeps bold, italic, links and colors. Attributes are compared with
/// `isEqual`, never interpreted, so this works for any keys.
///
/// - Unchanged runs keep their attributes, and deleted text is dropped.
/// - A pure insertion takes the previous character's attributes (the next one's at the
///   start), without extending a link it only touches.
/// - A replacement takes the attributes of the text it replaces. When that text spans more
///   than one format, the same words corrected (as many words, each a typo away) take theirs
///   word by word; anything else, such as a rewrite or a translation, keeps only what the
///   whole replaced text has in common.
///
/// Returns nil when the segments do not spell out `source.string`; the caller then writes
/// plain text.
public func carryAttributes(
  from source: NSAttributedString, along segments: [DiffSegment]
) -> NSAttributedString? {
  let old = segments.map { segment in
    switch segment {
    case .unchanged(let text): text
    case .changed(let from, _): from
    }
  }
  guard old.joined() == source.string else { return nil }

  let result = NSMutableAttributedString()
  var cursor = 0
  for segment in segments {
    switch segment {
    case .unchanged(let text):
      let range = NSRange(location: cursor, length: text.utf16.count)
      result.append(source.attributedSubstring(from: range))
      cursor += range.length
    case .changed(let from, let to):
      let range = NSRange(location: cursor, length: from.utf16.count)
      for (text, attributes) in replacementPieces(source, range: range, to: to) {
        result.append(NSAttributedString(string: text, attributes: attributes))
      }
      cursor += range.length
    }
  }
  return result
}

private typealias Attributes = [NSAttributedString.Key: Any]

/// AppKit's and UIKit's `.link`, which Foundation alone does not name.
let linkKey = NSAttributedString.Key("NSLink")

private func replacementPieces(
  _ source: NSAttributedString, range: NSRange, to: String
) -> [(String, Attributes)] {
  guard !to.isEmpty else { return [] }
  if range.length == 0 { return [(to, insertionAttributes(source, at: range.location))] }
  if runCount(source, range) == 1 {
    return [(to, source.attributes(at: range.location, effectiveRange: nil))]
  }
  let fromTokens = tokens((source.string as NSString).substring(with: range))
  let toTokens = tokens(to)
  // Word by word only for the same words corrected: a rewrite with as many words must not
  // scatter bold over unrelated ones.
  let sameWords =
    fromTokens.count == toTokens.count
    && zip(fromTokens, toTokens).allSatisfy { old, new in
      old.isSpace == new.isSpace && (old.isSpace || isTypoFix(old.text, new.text))
    }
  guard sameWords else { return [(to, commonAttributes(source, range))] }
  return zip(fromTokens, toTokens).map { old, new in
    let word = NSRange(location: range.location + old.offset, length: old.text.utf16.count)
    return (new.text, commonAttributes(source, word))
  }
}

private func insertionAttributes(_ source: NSAttributedString, at location: Int) -> Attributes {
  let previous = location > 0 ? source.attributes(at: location - 1, effectiveRange: nil) : nil
  let next = location < source.length ? source.attributes(at: location, effectiveRange: nil) : nil
  var attributes = previous ?? next ?? [:]
  if attributes[linkKey] != nil, !same(previous?[linkKey], next?[linkKey]) {
    attributes[linkKey] = nil
  }
  return attributes
}

private func runCount(_ source: NSAttributedString, _ range: NSRange) -> Int {
  var count = 0
  source.enumerateAttributes(in: range) { _, _, _ in count += 1 }
  return count
}

/// The attributes every character in `range` has, with equal values.
private func commonAttributes(_ source: NSAttributedString, _ range: NSRange) -> Attributes {
  var common: Attributes?
  source.enumerateAttributes(in: range) { attributes, _, _ in
    guard let current = common else {
      common = attributes
      return
    }
    common = current.filter { key, value in same(attributes[key], value) }
  }
  return common ?? [:]
}

private func same(_ a: Any?, _ b: Any?) -> Bool {
  switch (a, b) {
  case (nil, nil): true
  case (let a as NSObject, let b as NSObject): a.isEqual(b)
  default: false
  }
}

/// A typo-sized change: an edit distance of at most half the longer word, and at least 1.
private func isTypoFix(_ old: String, _ new: String) -> Bool {
  let a = Array(old.lowercased())
  let b = Array(new.lowercased())
  var row = Array(0...b.count)
  for i in a.indices {
    var next = [i + 1] + Array(repeating: 0, count: b.count)
    for j in b.indices {
      next[j + 1] = min(row[j + 1] + 1, next[j] + 1, row[j] + (a[i] == b[j] ? 0 : 1))
    }
    row = next
  }
  return row[b.count] <= max(1, max(a.count, b.count) / 2)
}

private struct Token {
  let text: String
  /// In UTF-16 units from the start of the tokenized text.
  let offset: Int
  let isSpace: Bool
}

/// Alternating runs of whitespace and of everything else.
private func tokens(_ text: String) -> [Token] {
  var result: [Token] = []
  var current = ""
  var start = 0
  var offset = 0
  var inSpace: Bool?
  for character in text {
    let isSpace = character.isWhitespace
    if let inSpace, inSpace != isSpace {
      result.append(Token(text: current, offset: start, isSpace: inSpace))
      current = ""
      start = offset
    }
    inSpace = isSpace
    current.append(character)
    offset += character.utf16.count
  }
  if let inSpace { result.append(Token(text: current, offset: start, isSpace: inSpace)) }
  return result
}
