// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Translation

/// The panel wording for translation results and failures (table `Translation`).
enum TranslationStrings {
  /// Action ids reported through `PanelController.onAction`.
  static let retryAction = "translation.retry"
  /// Opens Settings on the Model pane.
  static let openSettingsAction = "translation.openSettings"

  /// Under Apple Translation's result after the model failed. A missing or rejected key gets
  /// a button to Settings, or the user might never notice the model is not working.
  static func fallbackNote(_ error: any Error) -> PanelNote {
    PanelNote(
      String(
        format: String(
          localized: "The model failed (%@), so Apple Translation was used.",
          table: "Translation",
          comment:
            "Under a translation by Apple Translation after the model failed; %@ is the reason"),
        modelFailureReason(error)),
      action: isKeyProblem(error) ? openSettings(isDefault: false) : nil)
  }

  /// Under a partial model translation: why it stopped. Only a failed stream can be tried
  /// again; a key problem points to Settings, as elsewhere.
  static func partialNote(_ error: any Error) -> PanelNote {
    error as? ModelTranslationError == .truncated ? truncatedNote : incompleteNote(error)
  }

  static let truncatedNote = PanelNote(
    String(
      localized: "The translation was cut off at the length limit.", table: "Translation",
      comment: "Shown under a translation the model stopped early"))

  /// Under the text a model stream showed before it failed.
  static func incompleteNote(_ error: any Error) -> PanelNote {
    PanelNote(
      String(
        format: String(
          localized: "The translation is incomplete (%@).", table: "Translation",
          comment: "Under a translation whose stream failed partway; %@ is the reason"),
        modelFailureReason(error)),
      action: isKeyProblem(error) ? openSettings(isDefault: false) : retry(isDefault: false))
  }

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
      actions: [isKeyProblem(error) ? openSettings(isDefault: true) : retry(isDefault: true)])
  }

  /// The key is missing or the provider rejected it: only Settings can fix that.
  static func isKeyProblem(_ error: any Error) -> Bool {
    switch error {
    case ModelError.missingKey, ModelError.unauthorized: true
    default: false
    }
  }

  /// The notice for an error of Apple's framework when it translated without a model, or nil
  /// for cancellation. Languages it cannot translate on this Mac mean a model is needed.
  static func appleFailure(_ error: any Error) -> PanelPhase? {
    if error is CancellationError { return nil }
    if TranslationError.unsupportedLanguagePairing ~= error
      || TranslationError.unsupportedSourceLanguage ~= error
      || TranslationError.unsupportedTargetLanguage ~= error
      || isNotInstalled(error)
    {
      return .needsSetup(needsModel)
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
        message: message, actions: [retry(isDefault: true)]))
  }

  /// No model is set up and Apple Translation has no installed languages for the text.
  static let needsModel = PanelNotice(
    symbol: "key",
    title: String(
      localized: "Set up a model to translate", table: "Translation",
      comment: "Title when there is no model to translate with"),
    message: String(
      localized:
        "Dict translates with a model you choose, using your own API key. Add the key in Settings → Model, or use Ollama on this Mac.",
      table: "Translation", comment: "How to set up a model for translating"),
    actions: [openSettings(isDefault: true)])

  private static func isNotInstalled(_ error: any Error) -> Bool {
    if #available(macOS 26, *) { TranslationError.notInstalled ~= error } else { false }
  }

  private static func openSettings(isDefault: Bool) -> PanelAction {
    PanelAction(
      id: openSettingsAction,
      title: String(
        localized: "Open Settings", table: "Translation", comment: "Button that opens Settings"),
      isDefault: isDefault)
  }

  private static func retry(isDefault: Bool) -> PanelAction {
    PanelAction(
      id: retryAction,
      title: String(localized: "Try Again", table: "Translation", comment: "Retry button"),
      isDefault: isDefault)
  }

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
    case ModelError.emptyResponse, ModelError.malformedResponse, CardError.malformed:
      String(
        localized: "unexpected response", table: "Translation", comment: "Model failure reason")
    case ModelTranslationError.refused, CardStreamError.refused:
      String(
        localized: "blocked by the content filter", table: "Translation",
        comment: "Model failure reason")
    case ModelTranslationError.interrupted, CardStreamError.interrupted:
      String(
        localized: "the connection was interrupted", table: "Translation",
        comment: "Model failure reason")
    case ModelTranslationError.truncated, CardStreamError.truncated:
      String(
        localized: "the answer was cut off", table: "Translation",
        comment: "Model failure reason")
    default:
      String(
        localized: "unexpected error", table: "Translation", comment: "Model failure reason")
    }
  }
}
