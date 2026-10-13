// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// Clean-up and checks of a plain-text rewrite, the result of improving or translating out
// (architecture 6.7). Both are pure: the panel cleans the finished result, validates it, and
// asks for ⌘Return before replacing when there is any issue.

/// Which plain-text rewrite produced the result.
public enum RewriteAction: Sendable, Equatable { case improve, translateOut }

/// Why a rewrite should not replace the source without a second look. `validate` lists them
/// in this order.
public enum RewriteIssue: Sendable, Equatable, CaseIterable {
  /// Still starts with a code fence, or contains a `source_text_` tag, that the source does not.
  case wrapped
  /// Contains a sentence of our own prompt that the source does not.
  case echoedPrompt
  /// Translating out: the result reads as my language. Improving: the result's language
  /// differs from the source's.
  case languageMismatch
  /// Outside 0.3–4 times the source's UTF-8 length when translating out, 0.4–2 when improving;
  /// sources under 20 bytes are not judged.
  case lengthRatio
  /// A link of the source is not in the result verbatim.
  case lostURL
  /// The number of non-empty lines changed.
  case lineCountChanged
  /// Translating out: the result is the source as it was, although it needed translating.
  case unchanged
}

/// `result` as it goes into the text field: without a closing tag the model added, an
/// explanation it appended, and a code fence, tag, label or quotation marks around the whole
/// text that the source does not have; then with the source's own leading and trailing
/// whitespace, so a replaced paragraph keeps its line breaks. Blank stays blank.
public func cleanUp(_ result: String, source: String) -> String {
  let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
  var text = withoutEnclosure(
    result.trimmingCharacters(in: .whitespacesAndNewlines), source: trimmedSource)
  text = removingAddedClosingTag(text, source: source)
  text = removingAppendedNote(text, source: trimmedSource)
  text = withoutLabelAndQuotes(text, source: trimmedSource)
  guard !text.isEmpty else { return "" }
  let start = source.firstIndex { !$0.isWhitespace } ?? source.endIndex
  let end = source.lastIndex { !$0.isWhitespace }.map(source.index(after:)) ?? source.endIndex
  return source[..<start] + text + source[end...]
}

/// The issues of a cleaned `result`, in `RewriteIssue` order; empty when it can replace the
/// source. The language is judged with `resolveDirection`, the rules reading uses.
public func validate(
  source: String, result: String, action: RewriteAction, pair: LanguagePair
) -> [RewriteIssue] {
  let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
  let result = result.trimmingCharacters(in: .whitespacesAndNewlines)
  let sourceDirection = resolveDirection(source, pair: pair)
  let resultDirection = resolveDirection(result, pair: pair)
  var issues: [RewriteIssue] = []
  if (result.hasPrefix("```") && !source.hasPrefix("```"))
    || (contains(result, "source_text_") && !contains(source, "source_text_"))
  {
    issues.append(.wrapped)
  }
  if rewritePromptFragments.contains(where: { contains(result, $0) && !contains(source, $0) }) {
    issues.append(.echoedPrompt)
  }
  switch action {
  case .translateOut:
    if resultDirection == .intoLearning { issues.append(.languageMismatch) }
  case .improve:
    if sourceDirection != .undecided && resultDirection != .undecided
      && sourceDirection != resultDirection
    {
      issues.append(.languageMismatch)
    }
  }
  let bounds: ClosedRange<Double> = action == .translateOut ? 0.3...4 : 0.4...2
  if source.utf8.count >= 20,
    !bounds.contains(Double(result.utf8.count) / Double(source.utf8.count))
  {
    issues.append(.lengthRatio)
  }
  if links(in: source).contains(where: { !result.contains($0) }) { issues.append(.lostURL) }
  if nonEmptyLineCount(source) != nonEmptyLineCount(result) {
    issues.append(.lineCountChanged)
  }
  if action == .translateOut, result == source, sourceDirection == .intoLearning {
    issues.append(.unchanged)
  }
  return issues
}

// MARK: Clean-up steps

/// A label a model puts before the whole result, matched only at the very start.
nonisolated(unsafe) private let label =
  /^(?i:(?:english |chinese )?translation|translated text|rewritten text|rewrite|output|译文|翻译|改写|英文)\s*[:：]\s*/

/// A line of explanation a model appends.
nonisolated(unsafe) private let noteLine =
  /^\(?(?i:note|notes|explanation|translator'?s note|注|说明|备注)\s*[:：]/

/// A tag around the whole text.
nonisolated(unsafe) private let wrappingTag = /^<([A-Za-z_][\w.:-]*)[^>]*>([\s\S]*)<\/\1>$/

/// A code fence around the whole text, with an optional language name.
nonisolated(unsafe) private let wrappingFence = /^```[\w-]*\n([\s\S]*?)\n?```$/

private let quotePairs: [(open: Character, close: Character)] = [
  ("\"", "\""), ("“", "”"), ("'", "'"), ("‘", "’"), ("「", "」"), ("『", "』"),
]

/// Drops trailing explanation lines while the result has more non-empty lines than the
/// source: an explanation is never a translation of a line the source has.
private func removingAppendedNote(_ text: String, source: String) -> String {
  var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  let expected = nonEmptyLineCount(source)
  while nonEmptyLineCount(lines.joined(separator: "\n")) > expected,
    let last = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
    last.trimmingCharacters(in: .whitespaces).firstMatch(of: noteLine) != nil
  {
    while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
    lines.removeLast()
  }
  return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Removes a code fence, then a tag, around the whole text, each only when the source does not
/// start with one too.
private func withoutEnclosure(_ text: String, source: String) -> String {
  var text = text
  if !source.hasPrefix("```"), let match = text.wholeMatch(of: wrappingFence) {
    text = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
  }
  if !source.hasPrefix("<"), let match = text.wholeMatch(of: wrappingTag) {
    text = String(match.2).trimmingCharacters(in: .whitespacesAndNewlines)
  }
  return text
}

/// Removes a label, then quotation marks, around the whole text, each only when the source
/// does not have it too.
private func withoutLabelAndQuotes(_ text: String, source: String) -> String {
  var text = text
  if source.firstMatch(of: label) == nil, let match = text.firstMatch(of: label) {
    text = String(text[match.range.upperBound...])
  }
  for (open, close) in quotePairs where text.count >= 2 && source.first != open {
    guard text.first == open, text.last == close else { continue }
    let inner = text.dropFirst().dropLast()
    guard !inner.contains(open), !inner.contains(close) else { continue }
    text = inner.trimmingCharacters(in: .whitespacesAndNewlines)
    break
  }
  return text
}

// MARK: Checks

/// Sentences only our rewrite and translation prompts contain.
private let rewritePromptFragments = [
  "text-processing function", "not a chat assistant", "source block",
  "Output only the translation", "Output only the rewritten text",
  "send your translation as their own message",
]

private func contains(_ text: String, _ fragment: String) -> Bool {
  text.localizedCaseInsensitiveContains(fragment)
}

private func nonEmptyLineCount(_ text: String) -> Int {
  text.split(whereSeparator: \.isNewline).count {
    !$0.trimmingCharacters(in: .whitespaces).isEmpty
  }
}

/// The links `NSDataDetector` finds, as written in `text`.
private func links(in text: String) -> [String] {
  guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
  else { return [] }
  let range = NSRange(text.startIndex..., in: text)
  return detector.matches(in: text, range: range).compactMap { match in
    Range(match.range, in: text).map { String(text[$0]) }
  }
}
