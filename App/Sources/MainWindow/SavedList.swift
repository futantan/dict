// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// 生词本's filters (Design/main-app/saved.html).
enum SavedFilter: CaseIterable {
  case all, due, thisWeek, familiar
}

/// 生词本's orders, each newest or most first.
enum SavedSort: CaseIterable {
  case lastSeen, timesSeen, added
}

/// What 生词本 shows of the 要学 terms: searched, filtered and sorted, worked out from the
/// list `WindowData.saved` holds.
struct SavedList {
  /// The user's day, and the first day of the user's week: 「本周新加」 counts from it.
  let today: LocalDay
  let weekStart: LocalDay

  init(today: LocalDay, weekStart: LocalDay) {
    self.today = today
    self.weekStart = weekStart
  }

  /// The day the week of `now` began, by `calendar`'s first weekday, in `timeZone`.
  init(now: Date, timeZone: TimeZone, calendar: Calendar = .autoupdatingCurrent) {
    var calendar = calendar
    calendar.timeZone = timeZone
    let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
    self.init(today: LocalDay(now, in: timeZone), weekStart: LocalDay(start, in: timeZone))
  }

  func isDue(_ term: SavedTerm) -> Bool {
    term.dueDay.map { $0 <= today } ?? false
  }

  func matches(_ term: SavedTerm, _ filter: SavedFilter) -> Bool {
    switch filter {
    case .all: true
    case .due: isDue(term)
    case .thisWeek: term.learningDay.map { $0 >= weekStart } ?? false
    case .familiar: term.isFamiliar
    }
  }

  /// How many terms each filter keeps, before the search.
  func counts(_ terms: [SavedTerm]) -> [SavedFilter: Int] {
    Dictionary(
      uniqueKeysWithValues: SavedFilter.allCases.map { filter in
        (filter, terms.count { matches($0, filter) })
      })
  }

  /// The terms that pass `filter` and contain `search` in the word or its meaning, ignoring
  /// case and accents, in `sort`'s order; ties go to the most recently met.
  func visible(_ terms: [SavedTerm], search: String, filter: SavedFilter, sort: SavedSort)
    -> [SavedTerm]
  {
    let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
    return terms.filter { term in
      matches(term, filter)
        && (needle.isEmpty
          || [term.term.lemma, term.meaning, term.card?.definition ?? ""].contains {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
          })
    }
    .sorted { a, b in
      switch sort {
      case .timesSeen where a.term.encounterCount != b.term.encounterCount:
        return a.term.encounterCount > b.term.encounterCount
      case .added where a.learningDay != b.learningDay:
        // A term without a day goes last.
        guard let left = a.learningDay else { return false }
        guard let right = b.learningDay else { return true }
        return left > right
      default:
        return a.term.lastSeenAt != b.term.lastSeenAt
          ? a.term.lastSeenAt > b.term.lastSeenAt : a.term.id > b.term.id
      }
    }
  }
}
