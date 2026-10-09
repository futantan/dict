// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What the Read key does with a selection (architecture 10.1).
public enum ReadRoute: Sendable, Equatable {
  /// No letters or ideographs, a URL or an e-mail address: 「没有可查的内容」, no request.
  case nothing
  /// A word or phrase to look up: the dictionary layer and the model card.
  case lookUp
  /// A passage, or a word or phrase in my language, to translate.
  case translate
}

/// Routes by `classify`, then by language: a word or phrase in my language would get the
/// foreign words for it (architecture 10.1, rule 5), which does not exist yet, so it is
/// translated into the learning language instead.
public func readRoute(_ text: String, pair: LanguagePair) -> ReadRoute {
  switch classify(text) {
  case .none: .nothing
  case .passage: .translate
  case .word, .phrase: resolveDirection(text, pair: pair) == .intoLearning ? .translate : .lookUp
  }
}
