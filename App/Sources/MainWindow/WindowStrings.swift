// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The wording of the main window's pages (table `MainWindow`); the settings page's is in
/// `SettingsText` and the `Settings` table.
enum WindowStrings {
  static let readTag = String(
    localized: "Read", table: "MainWindow",
    comment: "Short tag on a translated sentence in a list: it came from the Read shortcut")
  static let writeTag = String(
    localized: "Write", table: "MainWindow",
    comment: "Short tag on a correction in a list: it came from the Write shortcut")

  // MARK: Sidebar

  static let readShortcut = String(
    localized: "Read: look up, translate", table: "MainWindow",
    comment: "Sidebar shortcut card: what the Read shortcut does")
  static let writeShortcut = String(
    localized: "Write: fix, translate out", table: "MainWindow",
    comment: "Sidebar shortcut card: what the Write shortcut does")
  static let noShortcut = String(
    localized: "None", table: "MainWindow",
    comment: "Sidebar shortcut card: the shortcut is not set")

  // MARK: Today

  static let searchPlaceholder = String(
    localized: "Look up a word, or type text to translate", table: "MainWindow",
    comment: "Placeholder of the search field on the Today page")
  static let overview = String(
    localized: "Today at a glance", table: "MainWindow",
    comment: "Accessibility label of the Today page's figures")
  static let lookedUpToday = String(
    localized: "Looked up today", table: "MainWindow", comment: "Today page figure label")
  static let wroteToday = String(
    localized: "Corrected and translated out today", table: "MainWindow",
    comment: "Today page figure label")
  static let dueLabel = String(
    localized: "To review", table: "MainWindow", comment: "Today page figure label")
  static let startReview = String(
    localized: "Start Review", table: "MainWindow", comment: "Button on the Today page")
  static let recent = String(
    localized: "Recent", table: "MainWindow", comment: "Heading of the Today page's recent lookups")
  static let allHistory = String(
    localized: "All History ›", table: "MainWindow",
    comment: "Link from the Today page to the History page")
  static let frequent = String(
    localized: "Met again and again, not learning yet", table: "MainWindow",
    comment: "Heading of the Today page's list of words met often but not marked to learn")
  static let learn = String(
    localized: "Learn", table: "MainWindow",
    comment: "Button that marks a word to learn, on the Today page")
  static let markToLearn = String(
    localized: "Mark to Learn", table: "MainWindow", comment: "Star button of a recent lookup")
  static let markedToLearn = String(
    localized: "Marked to Learn", table: "MainWindow",
    comment: "Star button of a recent lookup that is marked to learn")
  static let nothingYet = String(
    localized: "Nothing yet today. Select a word in any app and press the Read shortcut.",
    table: "MainWindow", comment: "The Today page's recent list when it is empty")
  static let nothingFrequent = String(
    localized: "Words you meet more than once show up here.", table: "MainWindow",
    comment: "The Today page's list of frequent words when it is empty")

  // A unit follows its big number without repeating it, so a plural variation can't pick
  // its form: the singular is its own string, "1 word" beside "12 words".

  /// 「个词 · 5 句」 after the big number of words.
  static func lookedUpUnit(terms: Int, sentences: Int) -> String {
    terms == 1
      ? String(
        localized: "word · \(sentences) sentences", table: "MainWindow",
        comment: "Unit after the big number 1 of words looked up today; the argument is sentences")
      : String(
        localized: "words · \(sentences) sentences", table: "MainWindow",
        comment: "Unit after the big number of words looked up today; the argument is sentences")
  }

  /// 「次 · 替换 6 次」.
  static func wroteUnit(count: Int, replaced: Int) -> String {
    count == 1
      ? String(
        localized: "time · replaced \(replaced)", table: "MainWindow",
        comment: "Unit after the number 1 of corrections and translations out today")
      : String(
        localized: "times · replaced \(replaced)", table: "MainWindow",
        comment: "Unit after the number of corrections and translations out today")
  }

  /// 「个词」 after the big number of words to review.
  static func dueUnit(_ count: Int) -> String {
    count == 1
      ? String(
        localized: "word", table: "MainWindow",
        comment: "Unit after the big number 1 of words to review")
      : String(
        localized: "words", table: "MainWindow",
        comment: "Unit after the big number of words to review")
  }

  /// 「第 5 次」.
  static func encounters(_ count: Int) -> String {
    String(
      localized: "Seen \(count) times", table: "MainWindow",
      comment: "Pill: how many times a word has been met")
  }
}
