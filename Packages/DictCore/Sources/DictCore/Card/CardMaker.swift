// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What a card stream reports, in order (architecture 6.6).
public enum CardEvent: Sendable, Equatable {
  /// The short fields received so far, each nil until its closing quote has arrived; sent
  /// whenever one of them changes, so the panel can show the meaning before the arrays.
  case fields(definition: String?, contextTranslation: String?)
  /// The model says the text is not a word or phrase; the stream ends here and the text
  /// should be translated instead.
  case notATerm
  /// The whole card, strictly decoded; the last event of an `ok` answer.
  case card(WordCard)
}

/// Why a card stream gave no card. A `ModelError` and `CardError.malformed` are thrown as
/// they are.
public enum CardStreamError: Error, Sendable, Equatable {
  /// The output limit cut the answer off.
  case truncated
  /// The provider's content filter stopped the answer.
  case refused
  /// The stream ended without a finish reason.
  case interrupted
}

/// Asks a `TextModel` for the card of a term with the prompt of `PromptBuilder.card`, and
/// reads the answer as it streams: the top-level strings first, the arrays once the answer
/// is complete.
public struct CardMaker: Sendable {
  public let model: any TextModel
  public let makeNonce: @Sendable () -> String

  public init(
    model: any TextModel,
    makeNonce: @escaping @Sendable () -> String = { PromptBuilder.makeNonce() }
  ) {
    self.model = model
    self.makeNonce = makeNonce
  }

  /// Cancelling the consuming task, or dropping the stream, cancels the request.
  public func card(
    term: String, context: String?, pair: LanguagePair, accent: Accent
  ) -> AsyncThrowingStream<CardEvent, Error> {
    let request = PromptBuilder.card(
      term: term, context: context, pair: pair, accent: accent, nonce: makeNonce())
    let model = model
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try await Self.read(model.stream(request), into: continuation)
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private static func read(
    _ stream: AsyncThrowingStream<StreamEvent, Error>,
    into continuation: AsyncThrowingStream<CardEvent, Error>.Continuation
  ) async throws {
    var received = ""
    var scanner = TopLevelFieldScanner()
    var shown: (String?, String?) = (nil, nil)
    var finish: FinishReason?
    for try await event in stream {
      switch event {
      case .thinking: continue
      case .text(let delta):
        received += delta
        scanner.feed(delta)
      case .discardText:
        received = ""
        scanner = TopLevelFieldScanner()
      case .finished(let reason, _):
        finish = reason
        continue
      }
      if scanner.values["status"] == WordCard.Status.notATerm.rawValue {
        continuation.yield(.notATerm)
        return
      }
      let fields = (scanner.values["definition"], scanner.values["contextTranslation"])
      if fields != shown, fields.0 != nil || fields.1 != nil {
        shown = fields
        continuation.yield(.fields(definition: fields.0, contextTranslation: fields.1))
      }
    }
    switch finish {
    case .complete: break
    case .truncated: throw CardStreamError.truncated
    case .refused: throw CardStreamError.refused
    case .unknown, nil: throw CardStreamError.interrupted
    }
    let card = try decodeCard(received)
    continuation.yield(card.status == .notATerm ? .notATerm : .card(card))
  }
}
