// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// The wording of the Write flow: the proofreading panel and the replacement toast (table
/// `Writing`).
enum WritingStrings {
  static let checking = String(
    localized: "Checking spelling and grammar…", table: "Writing",
    comment: "Panel footer while the selected text is being proofread")

  static let title = String(
    localized: "Proofread", table: "Writing", comment: "Panel footer title of the Write flow")

  static func changes(_ count: Int) -> String {
    String(
      localized: "\(count) changes", table: "Writing",
      comment: "Panel footer: how many corrections the proofread made")
  }

  /// How many of the changes are accepted; when all are, as `changes(_:)`.
  static func changes(_ accepted: Int, of count: Int) -> String {
    guard accepted != count else { return changes(count) }
    return String(
      localized: "\(accepted) of \(count) changes", table: "Writing",
      comment: "Panel footer: how many of the corrections are accepted, when not all are")
  }

  static let allDeclined = String(
    localized: "All changes declined", table: "Writing",
    comment: "Panel footer when the user declined every correction")

  static let nothingReplaced = String(
    localized: "Nothing replaced: accept a change first", table: "Writing",
    comment: "Panel footer after Return with every correction declined; nothing was replaced")

  static let reviewHelp = String(
    localized: "Click a change, or use ← → and Space, to accept or decline it", table: "Writing",
    comment: "Tooltip of the proofread text")

  static let noMistakes = String(
    localized: "No mistakes found", table: "Writing",
    comment: "Panel footer when the proofread changed nothing")

  static let cannotReplace = String(
    localized: "Can’t replace text in this app; copy it instead.", table: "Writing",
    comment: "Panel footer when the selection's field cannot be written")

  static let replaceAction = String(
    localized: "Replace", table: "Writing",
    comment: "Panel footer action that replaces the selection with the correction")

  static let copyAction = String(
    localized: "Copy", table: "Writing", comment: "Panel footer action that copies the correction")

  static let nothingToCheck = PanelNotice(
    symbol: "text.cursor",
    title: String(
      localized: "Select text to check", table: "Writing",
      comment: "Title when the Write shortcut found no selected text"),
    message: String(
      localized: "Select what you wrote, then press the Write shortcut again.", table: "Writing",
      comment: "How to use the Write shortcut"))

  /// No model is set up; proofreading needs one.
  static let needsModel = PanelNotice(
    symbol: "key.fill",
    title: String(
      localized: "Set up a model to proofread", table: "Writing",
      comment: "Title when there is no model to proofread with"),
    message: String(
      localized:
        "Dict proofreads with a model you choose, using your own API key. Add the key in Settings → Model, or use Ollama on this Mac.",
      table: "Writing", comment: "How to set up a model for proofreading"),
    actions: [
      PanelAction(
        id: TranslationStrings.openSettingsAction,
        title: String(
          localized: "Open Settings", table: "Writing", comment: "Button that opens Settings"),
        isDefault: true)
    ])

  static func proofreadFailure(_ error: any Error) -> PanelNotice {
    let isKeyProblem = TranslationStrings.isKeyProblem(error)
    return PanelNotice(
      title: String(
        localized: "The model couldn’t proofread this", table: "Writing",
        comment: "Title of the error when proofreading failed"),
      message: String(
        format: String(
          localized: "Reason: %@.", table: "Writing",
          comment: "Why proofreading failed; the argument is a short reason"),
        failureReason(error)),
      actions: [
        PanelAction(
          id: isKeyProblem ? TranslationStrings.openSettingsAction : TranslationStrings.retryAction,
          title: isKeyProblem
            ? String(
              localized: "Open Settings", table: "Writing", comment: "Button that opens Settings")
            : String(localized: "Try Again", table: "Writing", comment: "Retry button"),
          isDefault: true)
      ])
  }

  private static func failureReason(_ error: any Error) -> String {
    switch error {
    case ProofreadError.truncated:
      String(
        localized: "the answer was cut off", table: "Writing", comment: "Proofread failure reason")
    case ProofreadError.refused:
      String(
        localized: "blocked by the content filter", table: "Writing",
        comment: "Proofread failure reason")
    case ProofreadError.interrupted:
      String(
        localized: "the connection was interrupted", table: "Writing",
        comment: "Proofread failure reason")
    case ProofreadError.malformed:
      String(
        localized: "unexpected response", table: "Writing", comment: "Proofread failure reason")
    case ProofreadError.edits:
      String(
        localized: "the corrections didn’t match the text", table: "Writing",
        comment: "Proofread failure reason")
    default:
      TranslationStrings.modelFailureReason(error)
    }
  }

  // MARK: Toast

  static let replaced = String(
    localized: "Replaced · ⌘Z to undo", table: "Writing",
    comment: "Toast after the selection was replaced")

  static let notReplaced = String(
    localized: "The text changed, so it wasn’t replaced.", table: "Writing",
    comment: "Toast when the selection changed before replacing")

  static let unconfirmed = String(
    localized: "Couldn’t confirm the replacement. Please check the text.", table: "Writing",
    comment: "Toast when the field changed in an unexpected way")

  static let clipboardHoldsResult = String(
    localized: "Couldn’t confirm the replacement. The correction is on the clipboard.",
    table: "Writing",
    comment: "Toast when the paste could not be confirmed and the clipboard keeps the result")

  static let pasteFailed = String(
    localized: "Couldn’t paste into this app.", table: "Writing",
    comment: "Toast when the paste did not change the field")

  static let copyResult = String(
    localized: "Copy Correction", table: "Writing",
    comment: "Toast button that copies the correction")
}
