// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What the user asks for.
public enum Capability: Sendable {
  case translate, lookup, equivalents, proofread, improve, translateOut
}

/// What serves a capability.
public enum Engine: Sendable, Equatable {
  case model, appleTranslation, spellChecker, dictionaryOnly, unavailable
}

/// A translation backend: the model, or Apple's Translation framework.
public protocol Translator: Sendable {
  /// Each element is the whole translation so far. Apple's framework yields one element,
  /// the model yields progressively.
  func translate(_ text: String, from: Locale.Language?, to: Locale.Language)
    -> AsyncThrowingStream<String, Error>
}
