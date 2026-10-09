// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import NaturalLanguage

/// What a selection is, which decides whether it gets a word card, a translation or nothing.
public enum SelectionKind: Sendable, Equatable { case none, word, phrase, passage }

/// Classifies a selection by the ordered rules of architecture 5.1:
/// 1. `raw` is the text without surrounding whitespace; `core` is `raw` without surrounding
///    punctuation and symbols.
/// 2. `.none` when `core` is empty, has no letters or ideographs, or is a URL or an email.
/// 3. Without Han or kana, `core` with no inner whitespace is a `.word`: `e.g.`, `U.S.`,
///    `well-known`, `don't`.
/// 4. `raw` ending in `. ! ? 。 ！ ？ …` is a `.passage`.
/// 5. Without Han or kana, 2 to 6 whitespace-separated words are a `.phrase`, more a `.passage`.
/// 6. With Han or kana, by `NLTokenizer` words: 1 is a `.word`; 2 or 3 within 7 characters a
///    `.phrase`; anything else a `.passage`.
public func classify(_ text: String) -> SelectionKind {
  let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
  let core = raw.strippingEdges { $0.isWhitespace || $0.isPunctuation || $0.isSymbol }
  guard core.unicodeScalars.contains(where: \.properties.isAlphabetic), !isLink(core) else {
    return .none
  }

  let hasHanOrKana = core.unicodeScalars.contains {
    switch WritingScript.of($0) {
    case .han, .hiragana, .katakana: true
    default: false
    }
  }
  if !hasHanOrKana, !core.contains(where: \.isWhitespace) { return .word }
  if let last = raw.last, sentenceEnds.contains(last) { return .passage }

  guard hasHanOrKana else {
    let words = core.split(whereSeparator: \.isWhitespace).count
    return words <= 6 ? .phrase : .passage
  }
  let tokenizer = NLTokenizer(unit: .word)
  tokenizer.string = core
  let words = tokenizer.tokens(for: core.startIndex..<core.endIndex).count
  let characters = core.count { !$0.isWhitespace }
  switch words {
  case 1: return .word
  case 2...3 where characters <= 7: return .phrase
  default: return .passage
  }
}

private let sentenceEnds: Set<Character> = [".", "!", "?", "。", "！", "？", "…"]

/// Whether the whole text is one URL or email address.
private func isLink(_ text: String) -> Bool {
  guard
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
  else { return false }
  let whole = NSRange(text.startIndex..<text.endIndex, in: text)
  return detector.firstMatch(in: text, range: whole)?.range == whole
}

extension String {
  /// The text without the leading and trailing characters that match `isTrimmed`.
  fileprivate func strippingEdges(where isTrimmed: (Character) -> Bool) -> String {
    guard let first = firstIndex(where: { !isTrimmed($0) }),
      let last = lastIndex(where: { !isTrimmed($0) })
    else { return "" }
    return String(self[first...last])
  }
}
