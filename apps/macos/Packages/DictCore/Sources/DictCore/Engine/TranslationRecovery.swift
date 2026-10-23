// SPDX-License-Identifier: GPL-3.0-or-later

/// What to do when a model translation fails (architecture 6.4).
public enum TranslationRecovery: Sendable, Equatable {
  /// The session was cancelled: show nothing more.
  case stop
  /// Keep the text so far, marked incomplete, and say why. An incomplete translation is
  /// never used for replacing.
  case keepPartial
  /// Translate again with Apple's framework and say why.
  case fallBack
  /// Show the error.
  case showError
}

/// Decides how to recover from `error`, thrown by `ModelTranslator`; `hasText` is whether
/// any translation is showing. A translation cut off at the length limit is kept. Any other
/// failure falls back to Apple's framework when its languages are installed; without them,
/// text that already showed is kept as incomplete rather than replaced by the error.
public func translationRecovery(
  after error: any Error, hasText: Bool, appleTranslationInstalled: Bool
) -> TranslationRecovery {
  if error is CancellationError { return .stop }
  if hasText, error as? ModelTranslationError == .truncated { return .keepPartial }
  if appleTranslationInstalled { return .fallBack }
  return hasText ? .keepPartial : .showError
}
