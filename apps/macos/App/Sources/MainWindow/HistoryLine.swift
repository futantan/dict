// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

extension Activity {
  /// Unique across lookups and sentence events; the History page selects by it.
  var historyID: String {
    switch self {
    case .lookup(let lookup): "lookup-\(lookup.encounter.id)"
    case .sentence(let event): "sentence-\(event.id)"
    }
  }

  /// The user's day it was recorded on.
  var day: LocalDay {
    switch self {
    case .lookup(let lookup): lookup.encounter.day
    case .sentence(let event): event.day
    }
  }

  var sourceApp: String? {
    switch self {
    case .lookup(let lookup): lookup.encounter.sourceApp
    case .sentence(let event): event.sourceApp
    }
  }
}

/// One row of the History list (Design/main-app/history.html): the word or the text with its
/// tag, then the meaning and sentence or the other side, the app and time, and a word's star.
struct HistoryLine: Equatable, Identifiable {
  enum Title: Equatable {
    case word(String)
    /// A sentence; a translation's source, a translation out's result.
    case text(String)
    /// A correction or rewrite, its changes in place.
    case diff([DiffSegment])
  }

  let id: String
  let title: Title
  /// The part of speech, or what was done: 「翻译」, 「纠错」.
  let tag: String?
  let tagTone: Tone
  /// 「经营；管理 — She ran a small bakery.」, the translation, 「1 处修改 · 已替换」.
  let subtitle: String
  /// 「Safari · 14:20」; the day is the section's.
  let detail: String
  /// The term, and whether it is 要学; nil for a sentence.
  let termID: Int64?
  let isLearning: Bool

  init(
    _ activity: Activity, timeZone: TimeZone, locale: Locale,
    appName: (String) -> String? = { ActivityLine.appName(bundleID: $0) }
  ) {
    id = activity.historyID
    let time = activity.date.formatted(
      Date.FormatStyle(locale: locale, timeZone: timeZone).hour().minute())
    detail = [activity.sourceApp.flatMap(appName), time].compactMap(\.self)
      .joined(separator: " · ")
    switch activity {
    case .lookup(let lookup):
      let card = lookup.term.card.flatMap { try? decodeCard($0.json) }
      title = .word(lookup.term.lemma)
      tag = card.flatMap {
        $0.partOfSpeech.isEmpty ? nil : CardStrings.partOfSpeech($0.partOfSpeech)
      }
      tagTone = .accent
      let meaning = lookup.encounter.sense ?? card?.definition ?? ""
      subtitle = [meaning, lookup.encounter.sentence ?? ""].filter { !$0.isEmpty }
        .joined(separator: " — ")
      termID = lookup.term.id
      isLearning = lookup.term.tier == .learning
    case .sentence(let event):
      tag = HistoryStrings.tag(event.kind)
      termID = nil
      isLearning = false
      switch event.kind {
      case .translated:
        title = .text(event.source)
        subtitle = event.result
        tagTone = .accent
      case .translatedOut:
        title = .text(event.result)
        subtitle = event.source
        tagTone = .accent
      case .corrected, .improved:
        let segments = textDiff(event.source, event.result)
        title = .diff(segments)
        subtitle = Self.correctionSummary(segments, applied: event.applied)
        tagTone = .success
      }
    }
  }

  /// 「1 处修改 · 已替换」.
  static func correctionSummary(_ segments: [DiffSegment], applied: Bool) -> String {
    let changes = segments.filter { if case .changed = $0 { true } else { false } }.count
    return HistoryStrings.changes(changes) + " · "
      + (applied ? HistoryStrings.replaced : HistoryStrings.notReplaced)
  }
}

/// The entries of one day under its heading: 「今天」, 「昨天」, 「10 月 15 日」.
struct HistorySection: Equatable, Identifiable {
  let day: LocalDay
  let title: String
  let lines: [HistoryLine]

  var id: LocalDay { day }

  /// Groups `items`, newest first, into days in that order.
  static func group(
    _ items: [Activity], now: Date, timeZone: TimeZone, locale: Locale,
    appName: @escaping (String) -> String? = { ActivityLine.appName(bundleID: $0) }
  ) -> [HistorySection] {
    let today = LocalDay(now, in: timeZone)
    var sections: [HistorySection] = []
    var current: (day: LocalDay, lines: [HistoryLine])?
    func close() {
      guard let current else { return }
      sections.append(
        HistorySection(
          day: current.day,
          title: title(current.day, today: today, timeZone: timeZone, locale: locale),
          lines: current.lines))
    }
    for item in items {
      let line = HistoryLine(item, timeZone: timeZone, locale: locale, appName: appName)
      if current?.day == item.day {
        current?.lines.append(line)
      } else {
        close()
        current = (item.day, [line])
      }
    }
    close()
    return sections
  }

  /// 「今天」, 「昨天」, else the date, with the year when it is not this one.
  static func title(_ day: LocalDay, today: LocalDay, timeZone: TimeZone, locale: Locale)
    -> String
  {
    if day == today { return HistoryStrings.today }
    if day == today.adding(days: -1) { return HistoryStrings.yesterday }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let noon = calendar.date(
      from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
    var style = Date.FormatStyle(locale: locale, timeZone: timeZone).month(.abbreviated).day()
    if day.year != today.year { style = style.year() }
    return noon?.formatted(style) ?? day.description
  }
}
