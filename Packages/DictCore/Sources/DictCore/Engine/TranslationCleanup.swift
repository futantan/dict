// SPDX-License-Identifier: GPL-3.0-or-later

// Deterministic clean-up of a model's translation.
//
// When the source ends with a tag it leaves open (for example a forged `<source_text>`), the
// model almost always adds a line that closes the real source block, such as
// `</source_text_8e65ef39>`, although the prompt tells it not to. That line is not part of
// the translation.

/// Drops the last line of `translation` when it is only a closing tag that the model added:
/// one that `source` does not contain, or contains fewer times than `translation` (a forged
/// `</source_text>` earlier in the text, then the model's own on the last line). A
/// single-line translation is returned unchanged.
public func removingAddedClosingTag(_ translation: String, source: String) -> String {
  guard let (head, tail) = splitLastLine(translation) else { return translation }
  let tag = tail.trimmingCharacters(in: .whitespaces)
  guard tag.wholeMatch(of: closingTag) != nil,
    translation.ranges(of: tag).count > source.ranges(of: tag).count
  else { return translation }
  return head
}

/// What to show of a translation that is still streaming: a last line that is, or may still
/// grow into, a lone closing tag is held back until the stream ends, so a line that
/// `removingAddedClosingTag` would drop never flashes on screen.
public func streamingTranslation(_ partial: String) -> String {
  guard let (head, tail) = splitLastLine(partial) else { return partial }
  let line = tail.trimmingCharacters(in: .whitespaces)
  return line.wholeMatch(of: closingTagPrefix) != nil ? head : partial
}

/// `</name>` with an XML-like name.
nonisolated(unsafe) private let closingTag = /<\/[A-Za-z_][\w.:-]*>/
/// A non-empty prefix of a closing tag, the whole tag included.
nonisolated(unsafe) private let closingTagPrefix = /<(?:\/(?:[A-Za-z_][\w.:-]*>?)?)?/

/// Splits `text`, without trailing whitespace, into everything before its last line (also
/// without trailing whitespace) and that last line; nil when there is only one line.
private func splitLastLine(_ text: String) -> (head: String, tail: Substring)? {
  let trimmed = withoutTrailingWhitespace(text[...])
  guard let newline = trimmed.lastIndex(where: \.isNewline) else { return nil }
  return (
    String(withoutTrailingWhitespace(trimmed[..<newline])),
    trimmed[trimmed.index(after: newline)...]
  )
}

private func withoutTrailingWhitespace(_ text: Substring) -> Substring {
  let end = text.lastIndex { !$0.isWhitespace }.map(text.index(after:)) ?? text.startIndex
  return text[..<end]
}
