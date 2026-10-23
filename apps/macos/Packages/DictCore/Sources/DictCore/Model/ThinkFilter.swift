// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Removes thinking that leaks into the answer text (architecture 6.3).
///
/// An answer that starts with `<think>` is thinking up to the matching `</think>`. A
/// `</think>` without an opening tag means everything before it was thinking: the filter
/// emits `.discardText` and the answer restarts after the tag. Tags may be split across
/// deltas, so a possible partial tag is held back until the next delta decides it.
struct ThinkFilter: Sendable {
  private enum State { case start, thinking, answer }

  private static let open = "<think>"
  private static let close = "</think>"

  private var state = State.start
  private var pending = ""
  /// Set after a thinking block: the whitespace between it and the answer is dropped.
  private var trimLeading = false
  private var emittedText = false

  init() {}

  mutating func push(_ delta: String) -> [StreamEvent] {
    pending += delta
    var events: [StreamEvent] = []
    while true {
      switch state {
      case .start:
        let trimmed = pending.drop { $0.isWhitespace }
        if trimmed.hasPrefix(Self.open) {
          pending = String(trimmed.dropFirst(Self.open.count))
          state = .thinking
        } else if Self.open.hasPrefix(trimmed) {
          return events  // Still could be "<think>".
        } else {
          state = .answer
        }

      case .thinking:
        if let range = pending.range(of: Self.close) {
          if !pending[..<range.lowerBound].isEmpty { events.append(.thinking) }
          pending = String(pending[range.upperBound...])
          state = .answer
          trimLeading = true
        } else {
          let kept = Self.partialTagSuffix(of: pending, tag: Self.close)
          if pending.count > kept.count { events.append(.thinking) }
          pending = kept
          return events
        }

      case .answer:
        if let range = pending.range(of: Self.close, options: .backwards) {
          if emittedText { events.append(.discardText) }
          emittedText = false
          pending = String(pending[range.upperBound...])
          trimLeading = true
        }
        let kept = Self.partialTagSuffix(of: pending, tag: Self.close)
        emit(String(pending.dropLast(kept.count)), into: &events)
        pending = kept
        return events
      }
    }
  }

  /// Ends the stream: text held back as a possible tag is answer text after all.
  mutating func finish() -> [StreamEvent] {
    var events: [StreamEvent] = []
    if state != .thinking { emit(pending, into: &events) }
    pending = ""
    return events
  }

  private mutating func emit(_ text: String, into events: inout [StreamEvent]) {
    var text = Substring(text)
    if trimLeading {
      text = text.drop { $0.isWhitespace }
      if text.isEmpty { return }
      trimLeading = false
    }
    guard !text.isEmpty else { return }
    events.append(.text(String(text)))
    emittedText = true
  }

  /// The longest suffix of `text` that is a proper prefix of `tag`.
  private static func partialTagSuffix(of text: String, tag: String) -> String {
    for length in stride(from: min(tag.count - 1, text.count), to: 0, by: -1) {
      let suffix = text.suffix(length)
      if tag.hasPrefix(suffix) { return String(suffix) }
    }
    return ""
  }
}
