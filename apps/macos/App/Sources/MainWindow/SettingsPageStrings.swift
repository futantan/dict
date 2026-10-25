// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The wording of the settings page's sections beyond the old panes' (Design/main-app/
/// settings.html), in the `Settings` table with the rest of Settings.
extension SettingsText {
  // The old Languages and Shortcuts panes' wording, moved here unchanged.

  static let myLanguage = String(
    localized: "My language", table: "Settings", comment: "Settings field label")
  static let learningLanguage = String(
    localized: "Language I’m learning", table: "Settings", comment: "Settings field label")
  static let languagesNote = String(
    localized:
      "Text in your language is translated into the language you’re learning, and everything else into your language.",
    table: "Settings", comment: "Footer under the language pickers")
  static let accent = String(
    localized: "Accent", table: "Settings", comment: "Settings field label")
  static let shortcutsNote = String(
    localized:
      "Click a shortcut and press the new keys, or press a modifier key twice. Press Delete to remove it, or Esc to cancel.",
    table: "Settings", comment: "Footer under the shortcut fields")
  static let keepFormatting = String(
    localized: "Keep formatting when replacing", table: "Settings",
    comment: "Settings toggle label")
  static let keepFormattingNote = String(
    localized:
      "Return keeps bold, italics and links when it writes a correction or translation back. Only in native Mac apps.",
    table: "Settings", comment: "Subtitle under the keep formatting toggle")

  // New on the settings page.

  static let launchAtLogin = String(
    localized: "Launch at login", table: "Settings", comment: "Settings switch")
  static let loginNeedsApproval = String(
    localized: "Allow Dict in System Settings → General → Login Items.", table: "Settings",
    comment: "Under the launch at login switch when macOS waits for the user's approval")
  static let showInDock = String(
    localized: "Show in Dock", table: "Settings", comment: "Settings switch")
  static let showInMenuBar = String(
    localized: "Show icon in menu bar", table: "Settings", comment: "Settings switch")
  static let iconsNote = String(
    localized: "One of the two stays on, so you can always get back to Dict.", table: "Settings",
    comment: "Under the Dock or menu bar switch that cannot be turned off")
  static let keepRunning = String(
    localized: "Keep running after the window closes", table: "Settings",
    comment: "Settings switch")
  static let keepRunningNote = String(
    localized:
      "When this is off, closing the main window quits Dict and its shortcuts stop working.",
    table: "Settings", comment: "Under the keep running switch")

  static let accessibility = String(
    localized: "Accessibility", table: "Settings", comment: "Settings row: the permission")
  static let accessibilityNote = String(
    localized: "Reads the text you select and replaces it with the corrected result.",
    table: "Settings", comment: "Under the accessibility permission row")
  static let permissionOn = String(
    localized: "Allowed", table: "Settings", comment: "Pill: the permission is granted")
  static let permissionOff = String(
    localized: "Not allowed", table: "Settings", comment: "Pill: the permission is not granted")
  static let openSystemSettings = String(
    localized: "Open System Settings", table: "Settings", comment: "Button in a settings row")

  static func voice(language: String, name: String) -> String {
    String(
      localized: "\(language) voice · \(name)", table: "Settings",
      comment: "Settings row: the voice used; the arguments are the language and voice name")
  }
  static let noVoice = String(
    localized: "No voice", table: "Settings",
    comment: "Settings row title when no installed voice speaks the language")
  static let voiceIsGood = String(
    localized: "This voice sounds natural.", table: "Settings",
    comment: "Under the voice row when an enhanced or premium voice is used")

  static let recordsStayHere = String(
    localized: "Your history stays on this Mac", table: "Settings",
    comment: "Data and privacy: title of the note about where records are kept")
  static func recordsCount(terms: Int, sentences: Int) -> String {
    String(
      localized: "\(terms) words and \(sentences) sentences, never uploaded to any server.",
      table: "Settings", comment: "Data and privacy: what is kept on this Mac")
  }
  static let exportRecords = String(
    localized: "Export records", table: "Settings", comment: "Settings row")
  static let exportNote = String(
    localized: "A file Anki can import, with each word’s meaning and the sentence you met it in.",
    table: "Settings", comment: "Under the export row")
  static let exportButton = String(
    localized: "Export…", table: "Settings", comment: "Button that exports the records for Anki")
  static let exportFailed = String(
    localized: "Couldn’t export the records.", table: "Settings",
    comment: "Shown when writing the export file failed")
  static let clearRecords = String(
    localized: "Clear all records", table: "Settings", comment: "Settings row")
  static let clearButton = String(
    localized: "Clear All Records…", table: "Settings", comment: "Button that deletes all records")
  static let clearTitle = String(
    localized: "Clear all records?", table: "Settings", comment: "Title of the confirmation")
  static let clearMessage = String(
    localized:
      "Every word, sentence and review is deleted from this Mac, with your word list. This can’t be undone.",
    table: "Settings", comment: "Message of the confirmation before deleting all records")
  static let clearConfirm = String(
    localized: "Clear All", table: "Settings", comment: "Destructive button of the confirmation")

  static func appVersion(_ name: String, _ version: String) -> String {
    String(
      localized: "\(name) \(version)", table: "Settings",
      comment: "About: the app name and version")
  }
  static let checkForUpdates = String(
    localized: "Check for Updates", table: "Settings", comment: "Button in the About section")
  static let updatesOff = String(
    localized: "Updates are off in this build.", table: "Settings",
    comment: "About: this build has no updater")
  static let updatesOn = String(
    localized: "Dict checks for a new version once a day.", table: "Settings",
    comment: "About: what the updater does")
}

extension SettingsText {
  static let interfaceLanguage = String(
    localized: "App language", table: "Settings",
    comment: "Settings field label: the language of Dict's own text")
  static let interfaceLanguageRelaunch = String(
    localized: "Takes effect after Dict relaunches.", table: "Settings",
    comment: "Under the app language picker after choosing a language other than the current one")
  static let relaunchNow = String(
    localized: "Relaunch Now", table: "Settings",
    comment: "Button that quits Dict and opens it again in the chosen language")
}
