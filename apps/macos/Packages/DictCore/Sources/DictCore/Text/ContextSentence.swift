// SPDX-License-Identifier: GPL-3.0-or-later

/// The sentence around a selected term.
public struct ContextSentence: Sendable, Equatable {
  public let sentence: String
  /// Where the selected text sits in `sentence`, for highlighting and cloze cards.
  public let termRange: Range<String.Index>

  public init(sentence: String, termRange: Range<String.Index>) {
    self.sentence = sentence
    self.termRange = termRange
  }
}
