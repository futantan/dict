// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Observation

/// The History page's state: the filters, the entries loaded so far a page at a time, and
/// the selection. Part of `WindowData`, which owns it, so the page keeps its place when the
/// window switches pages and the gallery can pick what is selected.
@MainActor @Observable
final class HistoryModel {
  /// How many entries one read brings.
  @ObservationIgnored let pageSize: Int

  private(set) var filter = HistoryFilter()
  /// Newest first.
  private(set) var items: [Activity] = []
  private(set) var hasMore = false
  /// The apps anything was recorded in, the most used first, for the source filter.
  private(set) var apps: [String] = []
  private(set) var counts = HistoryCounts(total: 0, since: 0)
  /// False until the first read, so the list does not flash 「还没有记录」.
  private(set) var hasLoaded = false
  var selectedID: String?

  @ObservationIgnored private unowned let data: WindowData
  /// Bumped by every reload, so an older read that finishes late is dropped.
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var isLoadingMore = false

  init(data: WindowData, pageSize: Int = 100) {
    self.data = data
    self.pageSize = pageSize
  }

  var selected: Activity? {
    selectedID.flatMap { id in items.first { $0.historyID == id } }
  }

  // MARK: Filters

  func setKind(_ kind: HistoryKind) async {
    guard kind != filter.kind else { return }
    filter.kind = kind
    await reload()
  }

  func setSearch(_ text: String) async {
    guard text != filter.search else { return }
    filter.search = text
    await reload()
  }

  func setSourceApp(_ app: String?) async {
    guard app != filter.sourceApp else { return }
    filter.sourceApp = app
    await reload()
  }

  // MARK: Reading

  /// Reads the first page again, or as many entries as are loaded when `keepingLoaded`, so
  /// a change in place does not scroll the list back. The selection stays when its entry
  /// is still there, else moves to the first.
  func reload(keepingLoaded: Bool = false) async {
    generation += 1
    let generation = generation
    guard let vocab = data.vocab else {
      hasLoaded = true
      return
    }
    let limit = keepingLoaded ? max(items.count, pageSize) : pageSize
    do {
      let slice = try await vocab.history(filter, after: nil, limit: limit)
      let apps = try await vocab.historySourceApps()
      let counts = try await vocab.historyCounts(since: weekStart)
      guard generation == self.generation else { return }
      items = slice.items
      hasMore = slice.hasMore
      self.apps = apps
      self.counts = counts
      if selected == nil { selectedID = items.first?.historyID }
    } catch {
      Log.store.error("reading the history failed: \(String(describing: error), privacy: .public)")
    }
    hasLoaded = true
  }

  /// The next page, when there is one and none is on its way.
  func loadMore() async {
    guard hasMore, !isLoadingMore, let last = items.last, let vocab = data.vocab else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    let generation = generation
    do {
      let slice = try await vocab.history(
        filter, after: HistoryCursor(last), limit: pageSize)
      guard generation == self.generation else { return }
      items += slice.items
      hasMore = slice.hasMore
    } catch {
      Log.store.error(
        "reading more history failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// The first day of this week in the user's calendar, for 「本周」.
  private var weekStart: LocalDay {
    Self.weekStart(
      of: data.now(), timeZone: data.timeZone(),
      firstWeekday: Calendar.autoupdatingCurrent.firstWeekday)
  }

  static func weekStart(of date: Date, timeZone: TimeZone, firstWeekday: Int) -> LocalDay {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.firstWeekday = firstWeekday
    let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    return LocalDay(start, in: timeZone)
  }

  // MARK: Selection

  /// ↑ and ↓: the entry `offset` away, kept within the loaded ones. Nearing the end loads
  /// the next page.
  func moveSelection(by offset: Int) async {
    let ids = items.map(\.historyID)
    selectedID = Self.moving(selectedID, by: offset, in: ids)
    if let id = selectedID, let index = ids.firstIndex(of: id), index >= ids.count - 5 {
      await loadMore()
    }
  }

  /// The id `offset` away from `id` in `ids`, clamped; the first or last without a
  /// selection, nil for an empty list.
  static func moving(_ id: String?, by offset: Int, in ids: [String]) -> String? {
    guard !ids.isEmpty else { return nil }
    guard let id, let index = ids.firstIndex(of: id) else {
      return offset < 0 ? ids.last : ids.first
    }
    return ids[min(max(index + offset, 0), ids.count - 1)]
  }

  /// What to select once `id` is gone: the next entry, else the one before.
  static func neighbour(of id: String, in ids: [String]) -> String? {
    guard let index = ids.firstIndex(of: id) else { return ids.first }
    if index + 1 < ids.count { return ids[index + 1] }
    return index > 0 ? ids[index - 1] : nil
  }

  // MARK: Actions

  /// 要学 or back to 查过.
  func toggleLearning(_ lookup: DailyLog.Lookup) async {
    await data.setTier(lookup.term.tier == .learning ? .seen : .learning, termID: lookup.term.id)
    await reload(keepingLoaded: true)
  }

  /// Deletes the entry and selects its neighbour.
  func delete(_ activity: Activity) async {
    guard let vocab = data.vocab else { return }
    do {
      switch activity {
      case .lookup(let lookup): try await vocab.deleteEncounter(lookup.encounter.id)
      case .sentence(let event): try await vocab.deleteSentenceEvent(event.id)
      }
      Log.store.notice("deleted a history entry")
    } catch {
      Log.store.error(
        "deleting a history entry failed: \(String(describing: error), privacy: .public)")
    }
    if selectedID == activity.historyID {
      selectedID = Self.neighbour(of: activity.historyID, in: items.map(\.historyID))
    }
    await reload(keepingLoaded: true)
    await data.refresh()
  }
}
