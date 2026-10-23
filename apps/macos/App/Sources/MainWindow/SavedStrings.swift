// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// The wording of 生词本 (table `Saved`).
enum SavedStrings {
  static let subtitle = String(
    localized: "Words marked to learn", table: "Saved", comment: "Line above the Word List title")

  /// 「48 个词」 after the title.
  static func words(_ count: Int) -> String {
    String(
      localized: "\(count) words", table: "Saved",
      comment: "After the Word List title: how many words are marked to learn")
  }

  // MARK: Export

  static let export = String(
    localized: "Export", table: "Saved", comment: "Word List: title of the export menu")
  static let exportFormats = String(
    localized: "CSV, Anki", table: "Saved",
    comment: "Word List: the formats after the export menu's title")
  static let exportLabel = String(
    localized: "Export as CSV or for Anki", table: "Saved",
    comment: "Accessibility label of the Word List's export menu")
  static let exportCSV = String(
    localized: "Export as CSV…", table: "Saved", comment: "Word List export menu item")
  static let exportAnki = String(
    localized: "Export for Anki…", table: "Saved", comment: "Word List export menu item")

  // MARK: Toolbar

  static let searchPlaceholder = String(
    localized: "Search words or meanings", table: "Saved",
    comment: "Placeholder of the Word List's search field")
  static let searchLabel = String(
    localized: "Search the word list", table: "Saved",
    comment: "Accessibility label of the Word List's search field")
  static let filterLabel = String(
    localized: "Filter", table: "Saved", comment: "Accessibility label of the Word List's filters")
  static let sort = String(
    localized: "Sort", table: "Saved", comment: "Word List: before the current order")

  static func title(_ filter: SavedFilter) -> String {
    switch filter {
    case .all:
      String(localized: "All", table: "Saved", comment: "Word List filter")
    case .due:
      dueTag
    case .thisWeek:
      String(localized: "Added This Week", table: "Saved", comment: "Word List filter")
    case .familiar:
      familiar
    }
  }

  static func title(_ sort: SavedSort) -> String {
    switch sort {
    case .lastSeen: lastSeen
    case .timesSeen:
      String(localized: "Times Seen", table: "Saved", comment: "Word List order")
    case .added:
      String(localized: "Date Added", table: "Saved", comment: "Word List order")
    }
  }

  // MARK: Table

  static let wordColumn = String(
    localized: "Word", table: "Saved", comment: "Word List column header")
  static let meaningColumn = String(
    localized: "Meaning", table: "Saved", comment: "Word List column header")
  static let seenColumn = String(
    localized: "Seen", table: "Saved",
    comment: "Word List column header: how many times the word was met")
  static let lastSeen = String(
    localized: "Last Seen", table: "Saved",
    comment: "Word List column header and order: where and when the word was last met")
  static let reviewColumn = String(
    localized: "Review", table: "Saved", comment: "Word List column header: the next review")
  static let learningColumn = String(
    localized: "Learning", table: "Saved",
    comment: "Accessibility name of the Word List's star column")
  static let wordListLabel = String(
    localized: "Words", table: "Saved", comment: "Accessibility label of the Word List's table")
  /// 「第 6 次」 in the table's narrow column.
  static func timesSeen(_ count: Int) -> String {
    String(
      localized: "\(count) times", table: "Saved",
      comment: "Word List table pill: how many times the word was met")
  }

  /// 「待复习」 on a row of the table.
  static let duePill = String(
    localized: "Due", table: "Saved", comment: "Word List table pill: the word is due for review")
  static let dueTag = String(
    localized: "To Review", table: "Saved", comment: "Word List filter, and pill on a due word")
  static let familiar = String(
    localized: "Familiar", table: "Saved",
    comment: "Word List filter, and pill on a word remembered up to the longest interval")

  /// 「显示 10 / 48 个词」 under a filtered table.
  static func showing(_ shown: Int, of total: Int) -> String {
    String(
      localized: "Showing \(shown) of \(total)", table: "Saved",
      comment: "Under the Word List's table when a search or filter hides some words")
  }

  static func stopLearning(_ word: String) -> String {
    String(
      localized: "Stop learning “\(word)”", table: "Saved",
      comment: "Accessibility label of the filled star on a Word List row")
  }

  static let nothingSaved = String(
    localized:
      "No words to learn yet. Star a word on its card, or look it up on a few different days and it’s added for you.",
    table: "Saved", comment: "The Word List when no word is marked to learn")
  static let nothingMatches = String(
    localized: "No words match.", table: "Saved",
    comment: "The Word List when the search or filter hides every word")

  // MARK: Detail

  static let detailLabel = String(
    localized: "Word details", table: "Saved",
    comment: "Accessibility label of the Word List's detail pane")

  /// 「10 月 9 日加入」.
  static func added(_ day: String) -> String {
    String(
      localized: "Added \(day)", table: "Saved",
      comment: "Word List detail: the day the word was marked to learn")
  }

  /// 「10 月 19 日复习」.
  static func reviewOn(_ day: String) -> String {
    String(
      localized: "Review on \(day)", table: "Saved",
      comment: "Word List detail: the day of the word's next review")
  }

  static func otherSenses(_ senses: String) -> String {
    String(
      localized: "Other senses: \(senses)", table: "Saved",
      comment: "Word List detail: the word's other meanings")
  }

  static let metHeading = String(
    localized: "Where you met it", table: "Saved",
    comment: "Word List detail: heading of the sentences the word was met in")
  static let noSentence = String(
    localized: "Looked up on its own", table: "Saved",
    comment: "Word List detail: an encounter that has no sentence")
  static let openHistory = String(
    localized: "Open History ›", table: "Saved",
    comment: "Word List detail: link to the History page")
  static let reviewNow = String(
    localized: "Review Now", table: "Saved", comment: "Word List detail button")
  static let pronounce = String(
    localized: "Pronounce", table: "Saved", comment: "Word List detail button")
  static let stopLearningButton = String(
    localized: "Stop Learning", table: "Saved", comment: "Word List detail button")

  // MARK: Dates

  /// 「今天 14:02」, 「昨天 17:36」, 「10 月 15 日 16:48」; without the time when not `withTime`,
  /// as the table's narrow column has it: 「今天」, 「10 月 15 日」.
  static func when(
    _ date: Date, now: Date, timeZone: TimeZone, locale: Locale, withTime: Bool
  ) -> String {
    let day = LocalDay(date, in: timeZone)
    let today = LocalDay(now, in: timeZone)
    let time = date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).hour().minute())
    if day == today, !withTime {
      return String(localized: "Today", table: "Saved", comment: "When a word was met")
    }
    if day == today.adding(days: -1), !withTime {
      return String(localized: "Yesterday", table: "Saved", comment: "When a word was met")
    }
    if day == today {
      return String(
        localized: "Today \(time)", table: "Saved", comment: "When a word was met: today at a time")
    }
    if day == today.adding(days: -1) {
      return String(
        localized: "Yesterday \(time)", table: "Saved",
        comment: "When a word was met: yesterday at a time")
    }
    var style = Date.FormatStyle(locale: locale, timeZone: timeZone).month(.abbreviated).day()
    if withTime { style = style.hour().minute() }
    return date.formatted(style)
  }

  /// 「10 月 19 日」.
  static func day(_ day: LocalDay, locale: Locale) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let date =
      calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) ?? .now
    return date.formatted(
      Date.FormatStyle(locale: locale, timeZone: .gmt).month(.abbreviated).day())
  }
}
