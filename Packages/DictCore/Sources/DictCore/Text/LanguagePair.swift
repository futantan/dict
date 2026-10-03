// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The user's own language and the language they are learning.
public struct LanguagePair: Sendable, Equatable, Codable {
  public var mine: Locale.Language
  public var learning: Locale.Language

  /// Defaults to a Simplified Chinese speaker learning English.
  public init(
    mine: Locale.Language = Locale.Language(identifier: "zh-Hans"),
    learning: Locale.Language = Locale.Language(identifier: "en")
  ) {
    self.mine = mine
    self.learning = learning
  }
}

/// Which way a selection is translated.
public enum Direction: Sendable, Equatable { case intoMine, intoLearning, undecided }
