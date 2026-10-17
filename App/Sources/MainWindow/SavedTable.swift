// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import SwiftUI

/// What 生词本's rows and details need to write dates and app names.
struct SavedRowContext {
  let now: Date
  let timeZone: TimeZone
  let locale: Locale
  var appName: (String) -> String? = { ActivityLine.appName(bundleID: $0) }

  /// 「Safari · 今天 14:02」, or the time alone when the app is unknown.
  func seen(_ encounter: Encounter?, withTime: Bool) -> String {
    guard let encounter else { return "" }
    let when = SavedStrings.when(
      encounter.seenAt, now: now, timeZone: timeZone, locale: locale, withTime: withTime)
    return [encounter.sourceApp.flatMap(appName), when].compactMap(\.self)
      .joined(separator: " · ")
  }
}

/// The table of 要学 words in its card; it scrolls sideways when narrower than its columns.
struct SavedTable: View {
  let terms: [SavedTerm]
  /// Every 要学 word, for 「显示 10 / 48 个词」.
  let total: Int
  let selectedID: Int64?
  let list: SavedList
  let context: SavedRowContext
  let select: (Int64) -> Void
  let stopLearning: (Int64) -> Void

  @State private var width: CGFloat = 0

  var body: some View {
    WindowCard {
      ScrollView(.horizontal) {
        VStack(alignment: .leading, spacing: 0) {
          header
          if terms.isEmpty {
            EmptyCardText(text: SavedStrings.nothingMatches)
          }
          ForEach(terms, id: \.term.id) { term in
            row(term)
          }
        }
        .frame(width: max(width, WindowLayout.savedTableMinWidth), alignment: .leading)
      }
      .scrollIndicators(.automatic)
      .withoutScrollEdgeEffect()
      .onGeometryChange(for: CGFloat.self) {
        $0.size.width
      } action: {
        width = $0
      }
      if terms.count != total {
        CardDivider()
        Text(SavedStrings.showing(terms.count, of: total))
          .font(WindowType.detail.font)
          .foregroundStyle(Color(Palette.textSecondary))
          .padding(.horizontal, WindowLayout.cardRowHorizontal)
          .padding(.vertical, WindowLayout.savedHeaderVertical)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: WindowLayout.cardRadius, style: .continuous))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(SavedStrings.wordListLabel)
  }

  private var header: some View {
    HStack(spacing: 0) {
      cell(width: WindowLayout.savedWordColumn) { headerText(SavedStrings.wordColumn) }
      cell { headerText(SavedStrings.meaningColumn) }
      cell(width: WindowLayout.savedSeenColumn) { headerText(SavedStrings.seenColumn) }
      cell(width: WindowLayout.savedLastSeenColumn) { headerText(SavedStrings.lastSeen) }
      cell(width: WindowLayout.savedReviewColumn) { headerText(SavedStrings.reviewColumn) }
      Color.clear
        .frame(width: WindowLayout.savedStarColumn, height: 1)
        .accessibilityLabel(SavedStrings.learningColumn)
    }
    .padding(.vertical, WindowLayout.savedHeaderVertical - WindowLayout.savedCellVertical)
    .overlay(alignment: .bottom) { CardDivider() }
  }

  private func headerText(_ title: String) -> some View {
    Text(title)
      .font(WindowType.columnHeader.font)
      .foregroundStyle(Color(Palette.textSecondary))
      .lineLimit(1)
  }

  private func row(_ saved: SavedTerm) -> some View {
    let isSelected = saved.term.id == selectedID
    return HStack(spacing: 0) {
      cell(width: WindowLayout.savedWordColumn) {
        VStack(alignment: .leading, spacing: 2) {
          Text(saved.term.lemma)
            .font(WindowType.term.font)
            .foregroundStyle(Color(Palette.textPrimary))
          // A blank line without a phonetic, so every row is as tall.
          let phonetic = saved.card?.phonetic ?? ""
          Text(phonetic.isEmpty ? " " : phonetic)
            .font(WindowType.savedPhonetic.font)
            .foregroundStyle(Color(Palette.textSecondary))
            .accessibilityHidden(phonetic.isEmpty)
        }
        .lineLimit(1)
      }
      cell {
        HStack(spacing: Spacing.buttons) {
          if let pos = saved.card?.partOfSpeech, !pos.isEmpty {
            PartOfSpeechTag(name: pos)
          }
          Text(saved.meaning)
            .font(WindowType.row.font)
            .foregroundStyle(Color(Palette.textPrimary))
            .lineLimit(1)
        }
      }
      cell(width: WindowLayout.savedSeenColumn) {
        TablePill(text: SavedStrings.timesSeen(saved.term.encounterCount))
      }
      cell(width: WindowLayout.savedLastSeenColumn) {
        Text(context.seen(saved.encounters.first, withTime: false))
          .font(WindowType.footnote.font)
          .foregroundStyle(Color(Palette.textSecondary))
          .lineLimit(1)
      }
      cell(width: WindowLayout.savedReviewColumn) {
        ReviewStatus(term: saved, list: list, locale: context.locale)
      }
      IconButton(
        title: SavedStrings.stopLearning(saved.term.lemma), symbol: "star.fill", isOn: true
      ) {
        stopLearning(saved.term.id)
      }
      .frame(width: WindowLayout.savedStarColumn)
    }
    .background(isSelected ? Color(Palette.accentBlock) : .clear)
    .overlay(alignment: .leading) {
      if isSelected {
        Color(Palette.accent).frame(width: WindowLayout.savedSelectionBar)
      }
    }
    .overlay(alignment: .bottom) { CardDivider() }
    .contentShape(Rectangle())
    .onTapGesture { select(saved.term.id) }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityAction { select(saved.term.id) }
  }

  private func cell<Content: View>(
    width: CGFloat? = nil, @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .padding(.horizontal, WindowLayout.savedCellHorizontal)
      .padding(.vertical, WindowLayout.savedCellVertical)
      .frame(width: width, alignment: .leading)
      .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
  }
}

/// 「adj.」 on the accent tint, as on the Today page's rows.
struct PartOfSpeechTag: View {
  let name: String

  var body: some View {
    Text(CardStrings.partOfSpeech(name))
      .font(WindowType.badge.font)
      .foregroundStyle(Color(Palette.accentOnTint))
      .lineLimit(1)
      .padding(.horizontal, 6)
      .padding(.vertical, WindowLayout.tagVertical)
      .frame(minWidth: 28)
      .background(
        Color(Palette.accentTint),
        in: RoundedRectangle(cornerRadius: Radius.partOfSpeech, style: .continuous)
      )
      .fixedSize()
  }
}

/// The next review: 「待复习」 filled when due, 「已熟悉」 for a familiar word, else the day.
struct ReviewStatus: View {
  let term: SavedTerm
  let list: SavedList
  let locale: Locale

  var body: some View {
    if list.isDue(term) {
      TablePill(text: SavedStrings.duePill, isFilled: true)
    } else if term.isFamiliar {
      TablePill(text: SavedStrings.familiar, tone: .success)
    } else if let due = term.dueDay {
      Text(SavedStrings.day(due, locale: locale))
        .font(WindowType.footnote.font)
        .foregroundStyle(Color(Palette.textSecondary))
        .lineLimit(1)
    }
  }
}

/// The table's and the details' pill: the mockup's 12 pt capsule, on a tint or, for 「待复习」,
/// on the accent fill.
struct TablePill: View {
  let text: String
  var tone = Tone.accent
  var isFilled = false

  var body: some View {
    Text(text)
      .font(WindowType.badge.font)
      .foregroundStyle(isFilled ? .white : tone.onTint)
      .lineLimit(1)
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .background(isFilled ? Color(Palette.accentFill) : tone.tint, in: Capsule())
      .fixedSize()
  }
}
