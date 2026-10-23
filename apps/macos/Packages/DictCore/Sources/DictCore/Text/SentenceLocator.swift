// SPDX-License-Identifier: GPL-3.0-or-later

import NaturalLanguage

/// Finds the sentence of `paragraph` that contains `selection` (architecture 3.5).
/// Returns nil when the selection is empty or not inside one sentence of the paragraph.
///
/// Sentences come from `NLTokenizer(unit: .sentence)`, which keeps abbreviations (`e.g.`,
/// `Dr.`, `U.S.`), decimals, URLs and closing quotes and brackets inside the sentence, ends a
/// sentence at Chinese and Japanese punctuation, and always ends one at a line break.
/// Whitespace around the selection and the sentence is dropped; `termRange` points into the
/// returned sentence.
public func sentence(
  containing selection: Range<String.Index>, in paragraph: String
) -> ContextSentence? {
  guard let term = trimmed(selection, in: paragraph) else { return nil }
  let tokenizer = NLTokenizer(unit: .sentence)
  tokenizer.string = paragraph
  let sentenceRange = tokenizer.tokenRange(at: term.lowerBound)
  guard let sentenceRange = trimmed(sentenceRange, in: paragraph),
    sentenceRange.contains(term.lowerBound), sentenceRange.upperBound >= term.upperBound
  else { return nil }

  // Rebase the term onto the new string by UTF-16 offsets, which stay valid across the copy.
  let sentence = String(paragraph[sentenceRange])
  let utf16 = paragraph.utf16
  let lowerOffset = utf16.distance(from: sentenceRange.lowerBound, to: term.lowerBound)
  let length = utf16.distance(from: term.lowerBound, to: term.upperBound)
  let lower = sentence.utf16.index(sentence.utf16.startIndex, offsetBy: lowerOffset)
  let upper = sentence.utf16.index(lower, offsetBy: length)
  guard let lowerIndex = String.Index(lower, within: sentence),
    let upperIndex = String.Index(upper, within: sentence)
  else { return nil }
  return ContextSentence(sentence: sentence, termRange: lowerIndex..<upperIndex)
}

/// `range` without leading and trailing whitespace, or nil when nothing is left.
private func trimmed(_ range: Range<String.Index>, in text: String) -> Range<String.Index>? {
  let slice = text[range]
  guard let first = slice.firstIndex(where: { !$0.isWhitespace }),
    let last = slice.lastIndex(where: { !$0.isWhitespace })
  else { return nil }
  return first..<text.index(after: last)
}
