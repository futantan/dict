// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Why a model translation ended without a complete result. Thrown after the text so far.
public enum ModelTranslationError: Error, Sendable, Equatable {
  /// The output limit cut the translation off.
  case truncated
  /// The provider's content filter stopped the answer.
  case refused
  /// The stream ended without a finish reason.
  case interrupted
}

/// A model translation as its stream events arrive: the pure part of `ModelTranslator`.
public struct ModelTranslation: Sendable, Equatable {
  public let source: String
  /// Everything received since the start or the last `.discardText`.
  public private(set) var received = ""
  public private(set) var finish: FinishReason?

  public init(source: String) {
    self.source = source
  }

  public mutating func apply(_ event: StreamEvent) {
    switch event {
    case .thinking: break
    case .text(let delta): received += delta
    case .discardText: received = ""
    case .finished(let reason, _): finish = reason
    }
  }

  /// What to show: while streaming, without a last line that may become a lone closing tag;
  /// once finished, without a closing tag the model added (`removingAddedClosingTag`).
  public var text: String {
    finish == nil
      ? streamingTranslation(received) : removingAddedClosingTag(received, source: source)
  }
}

/// Translates with a `TextModel` and the prompts of `PromptBuilder`.
///
/// Each element is the whole translation so far, cleaned for display. A complete result ends
/// the stream normally. Otherwise the stream throws after the text so far: the model's
/// `ModelError`, `ModelError.emptyResponse` for a complete but blank answer, or a
/// `ModelTranslationError`. Cancelling the consuming task cancels the request.
public struct ModelTranslator: Translator {
  public let model: any TextModel
  public let makeNonce: @Sendable () -> String

  public init(
    model: any TextModel,
    makeNonce: @escaping @Sendable () -> String = { PromptBuilder.makeNonce() }
  ) {
    self.model = model
    self.makeNonce = makeNonce
  }

  /// Translates into `target`. The model recognizes the source language itself, so `from` is
  /// not used.
  public func translate(_ text: String, from: Locale.Language?, to target: Locale.Language)
    -> AsyncThrowingStream<String, Error>
  {
    run(PromptBuilder.translation(text, into: target, nonce: makeNonce()), source: text)
  }

  /// Translates the way the device decided, including `.undecided`, which `Translator` cannot
  /// express.
  public func translate(_ text: String, direction: Direction, pair: LanguagePair)
    -> AsyncThrowingStream<String, Error>
  {
    run(
      PromptBuilder.translation(text, direction: direction, pair: pair, nonce: makeNonce()),
      source: text)
  }

  private func run(_ request: ModelRequest, source: String) -> AsyncThrowingStream<String, Error> {
    let model = model
    return AsyncThrowingStream { continuation in
      let task = Task {
        var translation = ModelTranslation(source: source)
        var shown: String?
        func show() {
          guard translation.text != shown else { return }
          shown = translation.text
          continuation.yield(translation.text)
        }
        do {
          for try await event in model.stream(request) {
            translation.apply(event)
            if case .thinking = event { continue }
            show()
          }
          show()
          continuation.finish(throwing: Self.failure(of: translation))
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private static func failure(of translation: ModelTranslation) -> (any Error)? {
    switch translation.finish {
    case .complete:
      translation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? ModelError.emptyResponse : nil
    case .truncated: ModelTranslationError.truncated
    case .refused: ModelTranslationError.refused
    case .unknown, nil: ModelTranslationError.interrupted
    }
  }
}
