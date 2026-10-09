// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What translating the sample sentence showed.
public struct TranslationCheck: Sendable, Equatable {
  /// From sending the request to the first answer text, thinking not included.
  public var firstContent: Duration
  /// Whether the model sent thinking deltas, or thinking that leaked into the text.
  public var sawThinking: Bool

  public init(firstContent: Duration, sawThinking: Bool) {
    self.firstContent = firstContent
    self.sawThinking = sawThinking
  }
}

/// The checks of the settings "Test" button (architecture 6.8): translate a sentence and time
/// the first content; send a strict `json_schema` request and decode the answer strictly;
/// notice whether the model thinks. The caller runs them in order and shows each result.
public enum ModelCheck {
  /// Slower than this to the first content, the model is taken to be thinking.
  public static let slowFirstContent = Duration.seconds(3)

  static let sample = "Could you send me the report by Friday?"
  static let proofreadSample = "She go to school yesterday."

  /// Whether to warn that looking up words will be slow: thinking was seen, or the first
  /// content took longer than `slowFirstContent`.
  public static func isThinking(firstContent: Duration?, sawThinking: Bool) -> Bool {
    sawThinking || (firstContent.map { $0 > slowFirstContent } ?? false)
  }

  public static func translationRequest(into target: Locale.Language, nonce: String)
    -> ModelRequest
  {
    PromptBuilder.translation(sample, into: target, nonce: nonce)
  }

  /// The proofread request, a real strict schema; the card schema replaces it once the card
  /// prompt exists (M2.5).
  public static func structuredOutputRequest(nonce: String) -> ModelRequest {
    PromptBuilder.proofread(proofreadSample, nonce: nonce)
  }

  /// Translates the sample sentence into `target`. Throws the model's `ModelError`, or
  /// `ModelError.emptyResponse` when no answer text came back.
  public static func checkTranslation(
    _ model: any TextModel, into target: Locale.Language,
    clock: some Clock<Duration> = ContinuousClock(),
    makeNonce: @Sendable () -> String = { PromptBuilder.makeNonce() }
  ) async throws -> TranslationCheck {
    let start = clock.now
    var firstContent: Duration?
    var received = ""
    var sawThinking = false
    for try await event in model.stream(translationRequest(into: target, nonce: makeNonce())) {
      switch event {
      case .thinking:
        sawThinking = true
      case .text(let delta):
        if firstContent == nil { firstContent = start.duration(to: clock.now) }
        received += delta
      case .discardText:
        sawThinking = true
        firstContent = nil
        received = ""
      case .finished: break
      }
    }
    guard let firstContent, !received.allSatisfy(\.isWhitespace) else {
      throw ModelError.emptyResponse
    }
    return TranslationCheck(firstContent: firstContent, sawThinking: sawThinking)
  }

  /// Sends the strict `json_schema` request and decodes the complete answer strictly; only
  /// its shape counts, not whether the edits fit. Returns whether the model thought. Throws
  /// the model's `ModelError`, or a `ProofreadError` other than `.edits`.
  public static func checkStructuredOutput(
    _ model: any TextModel,
    makeNonce: @Sendable () -> String = { PromptBuilder.makeNonce() }
  ) async throws -> Bool {
    var received = ""
    var finish: FinishReason?
    var sawThinking = false
    for try await event in model.stream(structuredOutputRequest(nonce: makeNonce())) {
      switch event {
      case .thinking: sawThinking = true
      case .text(let delta): received += delta
      case .discardText:
        sawThinking = true
        received = ""
      case .finished(let reason, _): finish = reason
      }
    }
    switch finish {
    case .complete: break
    case .truncated: throw ProofreadError.truncated
    case .refused: throw ProofreadError.refused
    case .unknown, nil: throw ProofreadError.interrupted
    }
    _ = try decodeEdits(received)
    return sawThinking
  }
}
