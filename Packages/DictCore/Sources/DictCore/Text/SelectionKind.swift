// SPDX-License-Identifier: GPL-3.0-or-later

/// What a selection is, which decides whether it gets a word card, a translation or nothing.
public enum SelectionKind: Sendable, Equatable { case none, word, phrase, passage }

/// Classifies a selection by the ordered rules of architecture 5.1.
public func classify(_ text: String) -> SelectionKind {
  fatalError("classify is not implemented yet (M2.1)")
}
