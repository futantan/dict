// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Testing

@testable import DictApp

/// The History page's state and rows over the gallery's store
/// (Design/main-app/history.html).
@MainActor
struct HistoryTests {
  private let english = Locale(identifier: "en_US_POSIX")

  private func loaded(pageSize: Int = 100) async throws -> (WindowData, HistoryModel) {
    let data = try await MainWindowGallery.sampleData()
    let history = HistoryModel(data: data, pageSize: pageSize)
    await history.reload()
    return (data, history)
  }

  private func lines(_ history: HistoryModel) -> [HistoryLine] {
    history.items.map {
      HistoryLine(
        $0, timeZone: MainWindowGallery.timeZone, locale: english,
        appName: { $0 == "com.apple.Safari" ? "Safari" : nil })
    }
  }

  @Test func entriesAreGroupedByDayUnderTodayYesterdayAndTheDate() async throws {
    let (data, history) = try await loaded()
    defer { withExtendedLifetime(data) {} }

    let sections = HistorySection.group(
      history.items, now: MainWindowGallery.now, timeZone: MainWindowGallery.timeZone,
      locale: english, appName: { _ in nil })

    #expect(
      sections.map(\.title) == ["Today", "Yesterday", "Oct 15", "Oct 14", "Oct 13", "Oct 12", "Oct 9"])
    #expect(sections.map(\.lines.count).reduce(0, +) == history.items.count)
    #expect(history.counts.total == history.items.count)
    #expect(!history.hasMore)
  }

  @Test func aDateInAnotherYearShowsTheYear() throws {
    let today = MainWindowGallery.today
    let old = try #require(LocalDay(year: 2025, month: 12, day: 31))

    let title = HistorySection.title(
      old, today: today, timeZone: MainWindowGallery.timeZone, locale: english)

    #expect(title.contains("2025"))
  }

  @Test func rowsShowTheWordTheTextOrTheChanges() async throws {
    let (data, history) = try await loaded()
    defer { withExtendedLifetime(data) {} }
    let lines = lines(history)

    let run = try #require(lines.first)
    #expect(run.title == .word("run"))
    #expect(run.tag == "v.")
    #expect(run.subtitle == "经营；管理 — She ran a small bakery in the old town.")
    #expect(run.detail.hasPrefix("Safari · 2:20"))
    #expect(run.isLearning)

    let out = try #require(lines.first { $0.title == .text("I’m going to Berlin next week.") })
    #expect(out.subtitle == "我下周去柏林。")
    #expect(out.tag == "Out")
    #expect(out.termID == nil)

    let corrections = lines.filter { if case .diff = $0.title { true } else { false } }
    #expect(corrections.map(\.subtitle) == ["1 change · Replaced", "1 change · Not replaced"])
    guard case .diff(let segments) = corrections[1].title else { return }
    #expect(segments.contains(.changed(from: "hear", to: "hearing")))
  }

  @Test func filtersNarrowTheListAndKeepAValidSelection() async throws {
    let (data, history) = try await loaded()
    defer { withExtendedLifetime(data) {} }
    #expect(history.selectedID == history.items.first?.historyID)

    await history.setKind(.corrections)
    #expect(history.items.count == 2)
    #expect(history.selected != nil)

    await history.setKind(.all)
    await history.setSearch("bakery")
    #expect(history.items.map(\.historyID) == [history.selectedID])

    await history.setSearch("")
    await history.setSourceApp("com.apple.mail")
    #expect(history.items.allSatisfy { $0.sourceApp == "com.apple.mail" })
    #expect(history.apps.first == "com.apple.Safari")
  }

  @Test func pagesLoadAfterTheFirstWithoutRepeats() async throws {
    let (data, history) = try await loaded(pageSize: 20)
    defer { withExtendedLifetime(data) {} }
    #expect(history.items.count == 20)
    #expect(history.hasMore)

    while history.hasMore { await history.loadMore() }

    let ids = history.items.map(\.historyID)
    #expect(ids.count == history.counts.total)
    #expect(Set(ids).count == ids.count)
    #expect(history.items.map(\.date) == history.items.map(\.date).sorted(by: >))
  }

  @Test func arrowsMoveWithinTheListAndDeletingSelectsTheNeighbour() {
    let ids = ["a", "b", "c"]
    #expect(HistoryModel.moving("b", by: 1, in: ids) == "c")
    #expect(HistoryModel.moving("c", by: 1, in: ids) == "c")
    #expect(HistoryModel.moving("a", by: -1, in: ids) == "a")
    #expect(HistoryModel.moving(nil, by: 1, in: ids) == "a")
    #expect(HistoryModel.moving(nil, by: -1, in: ids) == "c")
    #expect(HistoryModel.moving("a", by: 1, in: []) == nil)

    #expect(HistoryModel.neighbour(of: "b", in: ids) == "c")
    #expect(HistoryModel.neighbour(of: "c", in: ids) == "b")
    #expect(HistoryModel.neighbour(of: "a", in: ["a"]) == nil)
  }

  @Test func thisWeekStartsOnTheUsersFirstWeekday() {
    let now = MainWindowGallery.now
    let zone = MainWindowGallery.timeZone
    #expect(
      HistoryModel.weekStart(of: now, timeZone: zone, firstWeekday: 2).description == "2026-10-12")
    #expect(
      HistoryModel.weekStart(of: now, timeZone: zone, firstWeekday: 1).description == "2026-10-11")
  }

  @Test func deletingAnEntrySelectsTheNextAndRefreshesTheWindow() async throws {
    let (data, history) = try await loaded()
    let run = try #require(history.items.first)
    let next = history.items[1].historyID
    let count = history.items.count

    await history.delete(run)

    #expect(history.items.count == count - 1)
    #expect(history.selectedID == next)
    #expect(data.today.counts.lookups == 11)
    // 要学 stays: the word keeps its other encounters and its place in the word list.
    #expect(data.learningCount == 12)
  }

  @Test func deletingASentenceRemovesOnlyIt() async throws {
    let (data, history) = try await loaded()
    let correction = try #require(
      history.items.first {
        if case .sentence(let event) = $0 { event.kind == .corrected } else { false }
      })

    await history.delete(correction)

    #expect(!history.items.contains(correction))
    #expect(data.totals.sentences == 13)
  }

  @Test func theLearnToggleUpdatesTheRowAndTheSidebar() async throws {
    let (data, history) = try await loaded()
    guard case .lookup(let run) = try #require(history.items.first) else {
      Issue.record("not a lookup")
      return
    }

    await history.toggleLearning(run)

    #expect(data.learningCount == 11)
    guard case .lookup(let after) = try #require(history.selected) else { return }
    #expect(after.term.tier == .seen)
  }

  @Test func aStoredLookupMakesThePanelsCardWithItsOwnSentence() async throws {
    let (data, history) = try await loaded()
    defer { withExtendedLifetime(data) {} }
    let lookups = history.items.compactMap { item -> DailyLog.Lookup? in
      if case .lookup(let lookup) = item { lookup } else { nil }
    }
    let today = try #require(lookups.first)
    let entry = MainWindowGallery.lexicon("ran", context: nil).first

    let card = CardState(lookup: today, entry: entry, accent: .american)

    #expect(card.lemma == "run")
    #expect(card.term == "ran")
    #expect(card.phonetic == "/rʌn/")
    #expect(card.transcription == .us)
    #expect(card.senses.count == CardState.shownSenses)
    #expect(card.sentenceMeaning == "经营；管理")
    #expect(card.context == "She ran a small bakery in the old town.")
    #expect(card.contextTranslation == "她在老城区经营一家小面包店。")
    #expect(card.otherSenses.count == 2)
    #expect(card.collocations.count == 3)
    #expect(card.model == .complete)
    #expect(card.encounters == 3)
    #expect(card.isLearning)

    // An earlier encounter keeps its own sentence and never borrows another's translation.
    let earlier = try #require(lookups.first { $0.term.lemma == "run" && $0 != today })
    let older = CardState(lookup: earlier, entry: nil, accent: .american)
    #expect(older.context == "We run a small team of designers.")
    #expect(older.contextTranslation == nil)
    #expect(older.mainSenses.first?.gloss == "经营；管理")
  }

  @Test func aLookupWithoutAStoredCardShowsTheDictionaryOnly() async throws {
    let store = try MainWindowGallery.makeStore()
    _ = try await store.recordLookup(
      LookupRecord(
        language: "en", lemma: "walk", surface: "walked", source: .typed,
        day: MainWindowGallery.today, seenAt: MainWindowGallery.now))
    guard case .lookup(let lookup) = try await store.recentActivity(limit: 1).first else {
      Issue.record("no lookup")
      return
    }

    let card = CardState(lookup: lookup, entry: nil, accent: .british)

    #expect(card.lemma == "walk")
    #expect(card.model == .unavailable)
    #expect(card.mainSenses.isEmpty)
    #expect(!card.showsSentenceSection)
  }
}
