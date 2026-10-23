// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// The wording of the History page (table `History`).
enum HistoryStrings {
  // MARK: Header and filters

  /// 「共 214 条 · 本周 63 条」.
  static func counts(total: Int, thisWeek: Int) -> String {
    let total = String(
      localized: "\(total) entries", table: "History",
      comment: "Above the History title: how many lookups and sentences there are in all")
    let week = String(
      localized: "\(thisWeek) this week", table: "History",
      comment: "Above the History title: how many lookups and sentences this week")
    return "\(total) · \(week)"
  }

  static let searchPlaceholder = String(
    localized: "Search words and sentences", table: "History",
    comment: "Placeholder of the History page's search field")
  static let searchLabel = String(
    localized: "Search History", table: "History",
    comment: "Accessibility label of the History page's search field")
  static let kindLabel = String(
    localized: "Entry Type", table: "History",
    comment: "Accessibility label of the History page's type filter")

  static func kind(_ kind: HistoryKind) -> String {
    switch kind {
    case .all:
      String(localized: "All", table: "History", comment: "History type filter: everything")
    case .words:
      String(localized: "Words", table: "History", comment: "History type filter: lookups")
    case .translations:
      String(
        localized: "Translations", table: "History",
        comment: "History type filter: sentences translated into my language")
    case .corrections:
      String(
        localized: "Corrections", table: "History",
        comment: "History type filter: corrections and rewrites")
    case .translationsOut:
      String(
        localized: "Translations Out", table: "History",
        comment: "History type filter: texts translated into the language being learnt")
    }
  }

  /// 「来源应用：全部」.
  static func sourceApp(_ name: String?) -> String {
    let name = name ?? allApps
    return String(
      localized: "Source App: \(name)", table: "History",
      comment: "History source app filter button; the argument is the app or All")
  }

  static let allApps = String(
    localized: "All", table: "History", comment: "History source app filter: every app")

  // MARK: List

  static let today = String(
    localized: "Today", table: "History", comment: "Heading of today's entries in History")
  static let yesterday = String(
    localized: "Yesterday", table: "History",
    comment: "Heading of yesterday's entries in History")

  static func tag(_ kind: SentenceKind) -> String {
    switch kind {
    case .translated:
      String(
        localized: "Translate", table: "History",
        comment: "Short tag of a translated sentence in History; fits a 44 pt chip")
    case .corrected:
      String(
        localized: "Fix", table: "History",
        comment: "Short tag of a correction in History; fits a 44 pt chip")
    case .improved:
      String(
        localized: "Rewrite", table: "History",
        comment: "Short tag of a rewrite in History; fits a 44 pt chip")
    case .translatedOut:
      String(
        localized: "Out", table: "History",
        comment: "Short tag of a translation into the language being learnt; fits a 44 pt chip")
    }
  }

  /// 「1 处修改」; 「没有修改」 for none.
  static func changes(_ count: Int) -> String {
    count == 0
      ? String(
        localized: "No changes", table: "History",
        comment: "A correction in History that changed nothing")
      : String(
        localized: "\(count) changes", table: "History",
        comment: "How many changes a correction in History made")
  }

  static let replaced = String(
    localized: "Replaced", table: "History",
    comment: "The result replaced the text in the other app")
  static let notReplaced = String(
    localized: "Not replaced", table: "History",
    comment: "The result did not replace the text in the other app")

  static let learning = String(
    localized: "Learning", table: "History",
    comment: "Accessibility label of the filled star of a word marked to learn")
  static let seen = String(
    localized: "Looked up", table: "History",
    comment: "Accessibility label of the outlined star of a word not marked to learn")

  static let nothingYet = String(
    localized: "Nothing recorded yet. Select a word in any app and press the Read shortcut.",
    table: "History", comment: "The History list when nothing has been recorded")
  static let noMatches = String(
    localized: "No entries match.", table: "History",
    comment: "The History list when the search or filters match nothing")
  static let selectSomething = String(
    localized: "Select an entry to see it here.", table: "History",
    comment: "The History detail pane when nothing is selected")

  // MARK: Detail

  /// 「原文 ran」: the text as met, when it differs from the word.
  static func surface(_ text: String) -> String {
    String(
      localized: "as “\(text)”", table: "History",
      comment: "After the word in History's detail: the form it was met in")
  }

  static let source = String(
    localized: "Source", table: "History", comment: "Small heading in History's detail")
  static let original = String(
    localized: "Original", table: "History",
    comment: "Small heading of the text before a translation or correction")
  static let result = String(
    localized: "Result", table: "History",
    comment: "Small heading of the translation or corrected text")

  /// 「第 3 次遇到」.
  static func encounters(_ count: Int) -> String {
    String(
      localized: "Met \(count) times", table: "History",
      comment: "Pill in History's detail: how many times the word has been met")
  }

  static let learn = String(
    localized: "Learn", table: "History", comment: "History detail button: mark to learn")
  static let pronounce = String(
    localized: "Pronounce", table: "History", comment: "History detail button")
  static let copy = String(
    localized: "Copy", table: "History", comment: "History detail button")
  static let openSource = String(
    localized: "Open Source", table: "History",
    comment: "History detail button: opens the web page the word was met on")
  static let delete = String(
    localized: "Delete This Entry", table: "History", comment: "History detail button")

  static let deleteTitle = String(
    localized: "Delete this entry?", table: "History",
    comment: "Title of the confirmation before deleting a History entry")
  static let deleteWordMessage = String(
    localized:
      "This lookup is removed from History. The word stays in your Word List if you are learning it.",
    table: "History", comment: "Message of the confirmation before deleting a lookup")
  static let deleteSentenceMessage = String(
    localized: "This entry is removed from History.", table: "History",
    comment: "Message of the confirmation before deleting a translation or correction")
  static let deleteConfirm = String(
    localized: "Delete", table: "History", comment: "Confirms deleting a History entry")
}
