// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Observation

/// What the main window reads from and writes to the vocabulary log. `VocabStore` is the
/// one implementation; the queries live in DictCore's `VocabStore+Window.swift`, and a page
/// that needs another adds it there and here.
protocol WindowVocab: Sendable {
  func dayCounts(on day: LocalDay) async throws -> DayCounts
  func recentActivity(limit: Int) async throws -> [Activity]
  func frequentNotLearning(minEncounters: Int, limit: Int) async throws -> [TermSummary]
  func dueCount(on day: LocalDay) async throws -> Int
  func learningCount() async throws -> Int
  func totals() async throws -> VocabTotals
  func setTier(_ tier: Tier, termID: Int64, on day: LocalDay) async throws
  func deleteAll() async throws
  func exportAnkiTSV() async throws -> Data

  // MARK: - Review

  func dueReviews(on day: LocalDay, limit: Int) async throws -> [ReviewItem]
  func reviewItem(termID: Int64) async throws -> ReviewItem?
  func reviewHistory(termID: Int64, excluding encounterID: Int64?) async throws -> ReviewHistory
  func nextDueDay(after day: LocalDay) async throws -> LocalDay?
  func recordReview(
    termID: Int64, encounterID: Int64?, rating: Rating, on day: LocalDay, at date: Date
  ) async throws

  // MARK: - History

  func history(_ filter: HistoryFilter, after cursor: HistoryCursor?, limit: Int) async throws
    -> HistorySlice
  func historySourceApps() async throws -> [String]
  func historyCounts(since day: LocalDay) async throws -> HistoryCounts
  func deleteEncounter(_ id: Int64) async throws
  func deleteSentenceEvent(_ id: Int64) async throws

  // MARK: - Saved

  func savedTerms() async throws -> [SavedTerm]
  func exportSavedCSV() async throws -> Data
}

extension VocabStore: WindowVocab {}

/// The Today page's content, read in one go.
struct TodaySnapshot: Equatable {
  var counts = DayCounts()
  var recent: [Activity] = []
  /// 「反复遇到，还没标要学」.
  var frequent: [TermSummary] = []
  var due = 0

  static let recentLimit = 5
  static let frequentLimit = 5
  /// Met this many times or more: once more than a single lookup.
  static let frequentMinimum = 2
}

/// The window's view of the vocabulary log: snapshots the pages draw, refreshed when the
/// window shows or changes something. Pages read it and call its actions; none of them
/// talks to the store.
@MainActor @Observable
final class WindowData {
  private(set) var today = TodaySnapshot()
  /// For the sidebar: 生词本's count and 复习's badge.
  private(set) var learningCount = 0
  private(set) var dueCount = 0
  private(set) var totals = VocabTotals(terms: 0, sentences: 0)
  /// Bumped by every refresh, so a page can re-read what lives outside the log, such as a
  /// permission, when the window comes back.
  private(set) var refreshID = 0
  /// False when the log could not be opened; the pages then say nothing was recorded.
  var isAvailable: Bool { vocab != nil }

  @ObservationIgnored let vocab: (any WindowVocab)?
  /// The current instant and the user's day; fixed in the gallery.
  @ObservationIgnored let now: () -> Date
  @ObservationIgnored let timeZone: () -> TimeZone

  init(
    vocab: (any WindowVocab)?, now: @escaping () -> Date = { .now },
    timeZone: @escaping () -> TimeZone = { .current }
  ) {
    self.vocab = vocab
    self.now = now
    self.timeZone = timeZone
  }

  var day: LocalDay { LocalDay(now(), in: timeZone()) }

  /// Reads everything the pages show; a failure is logged and leaves the last snapshot.
  func refresh() async {
    refreshID += 1
    guard let vocab else { return }
    let day = day
    do {
      let snapshot = TodaySnapshot(
        counts: try await vocab.dayCounts(on: day),
        recent: try await vocab.recentActivity(limit: TodaySnapshot.recentLimit),
        frequent: try await vocab.frequentNotLearning(
          minEncounters: TodaySnapshot.frequentMinimum, limit: TodaySnapshot.frequentLimit),
        due: try await vocab.dueCount(on: day))
      let learning = try await vocab.learningCount()
      let totals = try await vocab.totals()
      let saved = try await vocab.savedTerms()
      today = snapshot
      self.saved = saved
      dueCount = snapshot.due
      learningCount = learning
      self.totals = totals
    } catch {
      Log.store.error("window refresh failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// 要学 or back to 查过, then reads again.
  func setTier(_ tier: Tier, termID: Int64) async {
    guard let vocab else { return }
    do {
      try await vocab.setTier(tier, termID: termID, on: day)
    } catch {
      Log.store.error("changing a tier failed: \(String(describing: error), privacy: .public)")
    }
    await refresh()
  }

  func deleteAll() async {
    guard let vocab else { return }
    do {
      try await vocab.deleteAll()
      Log.store.notice("deleted every record")
    } catch {
      Log.store.error(
        "deleting every record failed: \(String(describing: error), privacy: .public)")
    }
    await refresh()
  }

  func exportAnki() async throws -> Data? {
    try await vocab?.exportAnkiTSV()
  }

  // MARK: - Review

  /// The review page's session; one per window, so it outlives the page's view.
  @ObservationIgnored private(set) lazy var review = ReviewModel(data: self)

  // MARK: - History

  /// The History page's filters, entries and selection.
  @ObservationIgnored private(set) lazy var history = HistoryModel(data: self)

  // MARK: - Saved

  /// 生词本: every 要学 term, the most recently met first; read with the rest by `refresh()`,
  /// so the page and the sidebar's count never disagree.
  private(set) var saved: [SavedTerm] = []

  func exportSavedCSV() async throws -> Data? {
    try await vocab?.exportSavedCSV()
  }
}
