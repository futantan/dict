// SPDX-License-Identifier: GPL-3.0-or-later

/// What to do when a model translation fails (architecture 6.4).
public enum TranslationRecovery: Sendable, Equatable {
  /// The session was cancelled: show nothing more.
  case stop
  /// Keep the text so far as the result and say it is cut off.
  case keepPartial
  /// Translate again with Apple's framework and say why.
  case fallBack
  /// Show the error.
  case showError
}

/// Decides how to recover from `error`, thrown by `ModelTranslator`. Any model failure falls
/// back to Apple's framework when its languages are installed; a cut-off translation is kept.
public func translationRecovery(
  after error: any Error, hasText: Bool, appleTranslationInstalled: Bool
) -> TranslationRecovery {
  if error is CancellationError { return .stop }
  if hasText, error as? ModelTranslationError == .truncated { return .keepPartial }
  return appleTranslationInstalled ? .fallBack : .showError
}
