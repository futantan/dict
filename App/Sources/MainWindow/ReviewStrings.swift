// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// The wording of the review page (table `Review`).
enum ReviewStrings {
  /// 「生词本 · 今天到期 9 个词」.
  static func dueToday(_ count: Int) -> String {
    String(
      localized: "Word List · \(count) words due today", table: "Review",
      comment: "Line above the Review page's title; the argument is how many words are due")
  }

  /// 「生词本 · 本轮 9 个词」: the N of 「n / N」, while the sidebar counts what is still due.
  static func thisSession(_ count: Int) -> String {
    String(
      localized: "Word List · \(count) words this session", table: "Review",
      comment: "Line above the Review page's title in a session; the argument is its word count")
  }

  static let end = String(
    localized: "End", table: "Review", comment: "Button that ends the review session")
  static let progress = String(
    localized: "Review progress", table: "Review",
    comment: "Accessibility label of the review session's progress bar")
  /// 「3 / 9」, read out.
  static func progressValue(_ done: Int, of total: Int) -> String {
    String(
      localized: "\(done) of \(total)", table: "Review",
      comment: "Accessibility value of the review progress: words rated of the session's words")
  }

  // MARK: Card

  static let card = String(
    localized: "Review card", table: "Review", comment: "Accessibility label of the review card")
  static let blank = String(
    localized: "blank", table: "Review",
    comment: "Read out in place of the hidden word in the review card's sentence")
  static let showAnswer = String(
    localized: "Show Answer", table: "Review", comment: "Button that reveals the review card")
  static let forgot = String(
    localized: "Forgot", table: "Review",
    comment: "Review rating button and the count of words rated so")
  static let remembered = String(
    localized: "Remembered", table: "Review",
    comment: "Review rating button and the count of words rated so")
  static let pronounce = String(
    localized: "Pronounce", table: "Review",
    comment: "Speaker button and key hint on the review card")
  static let spaceKey = String(
    localized: "Space", table: "Review", comment: "The space bar on a key cap")
  static let translation = String(
    localized: "This sentence", table: "Review",
    comment: "Small heading over the translation of the review card's sentence")

  /// 「另一次遇到 · Mail · 10 月 9 日」.
  static func alsoMet(_ detail: String) -> String {
    String(
      localized: "Also met · \(detail)", table: "Review",
      comment: "Heading over another sentence the word was met in; the argument is app and date")
  }

  /// 「上次：记得 · 3 天前」.
  static func lastTime(_ rating: Rating, when: String) -> String {
    let rated = rating == .good ? remembered : forgot
    return String(
      localized: "Last time: \(rated) · \(when)", table: "Review",
      comment: "Under the review card: the word's previous rating and how long ago")
  }

  // MARK: Summary

  static let summary = String(
    localized: "Today’s review", table: "Review",
    comment: "Accessibility label of the review page's summary")
  static let reviewedToday = String(
    localized: "Reviewed today", table: "Review", comment: "Review summary label")
  /// The unit after the big number of words reviewed: 「个词」.
  /// The unit does not repeat the number, so it has a string for one and one for more.
  static func wordsUnit(_ count: Int) -> String {
    count == 1
      ? String(
        localized: "word", table: "Review", comment: "Unit after the big number 1 of words reviewed"
      )
      : String(
        localized: "words", table: "Review",
        comment: "Unit after the big number of words reviewed, other than 1")
  }

  static let againNote = String(
    localized: "Forgotten words come back once at the end of this session.", table: "Review",
    comment: "Note in the review summary")

  // MARK: Done and empty

  static let doneTitle = String(
    localized: "Today’s review is done", table: "Review",
    comment: "Title when every word due today is reviewed")
  static let stoppedTitle = String(
    localized: "Stopped for now", table: "Review",
    comment: "Title after ending a review session with words still due")
  static let emptyTitle = String(
    localized: "Nothing to review today", table: "Review",
    comment: "Title of the Review page when no word is due")

  static func stillDue(_ count: Int) -> String {
    String(
      localized: "\(count) words still due today.", table: "Review",
      comment: "After ending a session early; the argument is how many words are still due")
  }

  /// 「下一次复习：明天」.
  static func nextReview(_ when: String) -> String {
    String(
      localized: "Next review: \(when).", table: "Review",
      comment: "When the next words are due; the argument is a day")
  }

  static let howItWorks = String(
    localized: "Words you mark to learn in the Word List come up here the next day.",
    table: "Review", comment: "Review page when nothing is learnt yet")
  static let continueReview = String(
    localized: "Continue Review", table: "Review",
    comment: "Button that starts another session with the words still due")
  static let openWordList = String(
    localized: "Open Word List ›", table: "Review",
    comment: "Link from the Review page to the Word List")
}

/// The days of the review page, in the interface's language.
enum ReviewDates {
  /// 「10 月 16 日」, with the year when it is not this year's.
  static func day(_ day: LocalDay, today: LocalDay, locale: Locale) -> String {
    var style = Date.FormatStyle(locale: locale, timeZone: .gmt).month(.abbreviated).day()
    if day.year != today.year { style = style.year() }
    return date(day).formatted(style)
  }

  /// When the next review is: 「明天」, else the day.
  static func next(_ next: LocalDay, today: LocalDay, locale: Locale) -> String {
    next == today.adding(days: 1)
      ? relative(days: 1, locale: locale) : day(next, today: today, locale: locale)
  }

  /// How long ago, in days: 「今天」, 「昨天」, 「3 天前」.
  static func ago(_ date: Date, today: LocalDay, timeZone: TimeZone, locale: Locale) -> String {
    let then = Self.date(LocalDay(date, in: timeZone))
    let days = gmt.dateComponents([.day], from: then, to: Self.date(today)).day ?? 0
    return relative(days: -max(days, 0), locale: locale)
  }

  private static func relative(days: Int, locale: Locale) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = locale
    formatter.dateTimeStyle = .named
    formatter.unitsStyle = .full
    return formatter.localizedString(from: DateComponents(day: days))
  }

  /// Midnight of `day` in GMT, where the day's arithmetic happens.
  private static func date(_ day: LocalDay) -> Date {
    gmt.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) ?? .distantPast
  }

  private static let gmt: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()
}
