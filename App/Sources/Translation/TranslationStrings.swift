// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Translation

/// The panel wording for translation results and failures (table `Translation`).
enum TranslationStrings {
  /// Action ids reported through `PanelController.onAction`.
  static let retryAction = "translation.retry"
  static let openSettingsAction = "translation.openSettings"

  static func fallbackNote(_ error: any Error) -> String {
    String(
      format: String(
        localized: "The model failed (%@), so Apple Translation was used.", table: "Translation",
        comment: "Under a translation by Apple Translation after the model failed; %@ is the reason"
      ),
      modelFailureReason(error))
  }

  static let truncatedNote = String(
    localized: "The translation was cut off at the length limit.", table: "Translation",
    comment: "Shown under a translation the model stopped early")

  static func modelFailure(_ error: any Error) -> PanelNotice {
    PanelNotice(
      title: String(
        localized: "The model couldn’t translate this", table: "Translation",
        comment: "Title of the error when the model translation failed"),
      message: String(
        format: String(
          localized: "Reason: %@.", table: "Translation",
          comment: "Why the model failed; the argument is a short reason"),
        modelFailureReason(error)),
      actions: [retry])
  }

  /// The notice for an error of Apple's framework, or nil for cancellation.
  static func appleFailure(_ error: any Error) -> PanelPhase? {
    if error is CancellationError { return nil }
    if TranslationError.unsupportedLanguagePairing ~= error
      || TranslationError.unsupportedSourceLanguage ~= error
      || TranslationError.unsupportedTargetLanguage ~= error
    {
      return .needsSetup(unsupportedPair)
    }
    if #available(macOS 26, *), TranslationError.notInstalled ~= error {
      return .needsSetup(
        PanelNotice(
          symbol: "arrow.down.circle.fill",
          title: String(
            localized: "Translation languages aren’t downloaded", table: "Translation",
            comment: "Title when Apple Translation lacks a language pack"),
          message: String(
            localized:
              "Download them in System Settings → General → Language & Region → Translation Languages.",
            table: "Translation", comment: "How to download Apple Translation languages")))
    }
    let message =
      TranslationError.unableToIdentifyLanguage ~= error
      ? String(
        localized: "Couldn’t tell which language the text is in.", table: "Translation",
        comment: "Apple Translation could not recognize the source language")
      : String(
        localized: "Something went wrong in Apple Translation.", table: "Translation",
        comment: "Apple Translation failed for another reason")
    return .failure(
      PanelNotice(
        title: String(
          localized: "Apple Translation couldn’t translate this", table: "Translation",
          comment: "Title of the error when Apple Translation failed"),
        message: message, actions: [retry]))
  }

  /// Neither a model nor Apple Translation can translate this pair.
  static let unsupportedPair = PanelNotice(
    symbol: "globe",
    title: String(
      localized: "Apple Translation doesn’t support these languages", table: "Translation",
      comment: "Title when no engine can translate the text"),
    message: String(
      localized: "Set up a model in Settings to translate them.", table: "Translation",
      comment: "How to translate a language pair Apple Translation does not support"),
    actions: [
      PanelAction(
        id: openSettingsAction,
        title: String(
          localized: "Open Settings", table: "Translation", comment: "Button that opens Settings"),
        isDefault: true)
    ])

  private static let retry = PanelAction(
    id: retryAction,
    title: String(localized: "Try Again", table: "Translation", comment: "Retry button"),
    isDefault: true)

  /// A short reason, used inside a sentence.
  static func modelFailureReason(_ error: any Error) -> String {
    switch error {
    case ModelError.missingKey:
      String(localized: "no API key", table: "Translation", comment: "Model failure reason")
    case ModelError.unauthorized:
      String(
        localized: "the API key was rejected", table: "Translation",
        comment: "Model failure reason")
    case ModelError.modelNotFound:
      String(localized: "model not found", table: "Translation", comment: "Model failure reason")
    case ModelError.rateLimited:
      String(
        localized: "rate or usage limit reached", table: "Translation",
        comment: "Model failure reason")
    case ModelError.badRequest:
      String(
        localized: "the request was rejected", table: "Translation",
        comment: "Model failure reason")
    case ModelError.server:
      String(
        localized: "the provider had an error", table: "Translation",
        comment: "Model failure reason")
    case ModelError.network:
      String(localized: "network error", table: "Translation", comment: "Model failure reason")
    case ModelError.timedOut:
      String(localized: "timed out", table: "Translation", comment: "Model failure reason")
    case ModelError.emptyResponse, ModelError.malformedResponse:
      String(
        localized: "unexpected response", table: "Translation", comment: "Model failure reason")
    case ModelTranslationError.refused:
      String(
        localized: "blocked by the content filter", table: "Translation",
        comment: "Model failure reason")
    case ModelTranslationError.interrupted:
      String(
        localized: "the connection was interrupted", table: "Translation",
        comment: "Model failure reason")
    case ModelTranslationError.truncated:
      String(
        localized: "the answer was cut off", table: "Translation",
        comment: "Model failure reason")
    default:
      String(
        localized: "unexpected error", table: "Translation", comment: "Model failure reason")
    }
  }
}
