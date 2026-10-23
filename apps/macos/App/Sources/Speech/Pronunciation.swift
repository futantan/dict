// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The rate of each ⌘P on a card: normal, and slow when it follows a normal one closely
/// (architecture 9, 11.5). A press after a slow one, or after a pause, is normal again.
struct PronunciationPace {
  /// How soon a press must follow the previous one to count as "again".
  static let window = Duration.seconds(3)

  private var last: (rate: SpeechRate, at: ContinuousClock.Instant)?

  mutating func next(at now: ContinuousClock.Instant) -> SpeechRate {
    let rate: SpeechRate =
      if let last, last.rate == .normal, now - last.at < Self.window { .slow } else { .normal }
    last = (rate, now)
    return rate
  }
}

extension Speaker {
  /// Speaks `text` and consumes the events until the speech ends, which a dropped stream
  /// would otherwise stop at once. A missing voice is logged; the card has nothing to show
  /// for it yet.
  @discardableResult
  func say(_ text: String, language: Locale.Language, rate: SpeechRate) -> Task<Void, Never> {
    let stream = speak(text, language: language, rate: rate)
    return Task {
      do {
        for try await _ in stream {}
      } catch {
        Log.ui.error("speech failed: \(String(describing: error), privacy: .public)")
      }
    }
  }
}
