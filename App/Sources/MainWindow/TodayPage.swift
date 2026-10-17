// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import SwiftUI

/// 今天 (Design/main-app/home.html): the search field, today's figures, the recent lookups
/// and the words met often but not marked to learn.
struct TodayPage: View {
  let data: WindowData
  let navigation: MainNavigation
  /// Looks up or translates the text in the result panel; the rect is the search field's,
  /// in the window's content, top-left origin.
  let lookUp: (String, CGRect) -> Void

  @State private var query = ""
  @State private var fieldFrame = CGRect.zero
  @FocusState private var isSearchFocused: Bool

  var body: some View {
    PageScaffold(title: MainSection.today.title, subtitle: dateLine) {
      VStack(alignment: .leading, spacing: WindowLayout.pageSpacing) {
        searchField
        figures
        HStack(alignment: .top, spacing: WindowLayout.pageSpacing) {
          recent
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
          frequent
            .frame(
              minWidth: WindowLayout.sideColumnMinWidth, maxWidth: WindowLayout.sideColumnMaxWidth)
        }
      }
    }
    .onChange(of: navigation.searchFocusRequest, initial: true) { _, request in
      if request > 0 { isSearchFocused = true }
    }
  }

  private var dateLine: String {
    data.now().formatted(
      Date.FormatStyle(locale: SettingsText.uiLocale, timeZone: data.timeZone())
        .month(.abbreviated).day().weekday(.wide))
  }

  // MARK: Search

  private var searchField: some View {
    HStack(spacing: Spacing.pill) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: Size.symbol + 2, weight: Size.symbolWeight))
        .foregroundStyle(Color(Palette.textTertiary))
        .accessibilityHidden(true)
      // The system's colours: the placeholder in the placeholder grey, the text as labels.
      TextField(WindowStrings.searchPlaceholder, text: $query)
        .textFieldStyle(.plain)
        .font(WindowType.search.font)
        .focused($isSearchFocused)
        .onSubmit(submit)
      KeyCap(keys: "⌘K")
        .foregroundStyle(Color(Palette.textSecondary))
    }
    .padding(.horizontal, Spacing.input)
    .frame(height: WindowLayout.searchHeight)
    .background(
      Color(Palette.cardFill),
      in: RoundedRectangle(cornerRadius: WindowLayout.cardRadius, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: WindowLayout.cardRadius, style: .continuous)
        .strokeBorder(Color(Palette.separator), lineWidth: 0.5)
    )
    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    .onGeometryChange(for: CGRect.self) {
      $0.frame(in: .global)
    } action: {
      fieldFrame = $0
    }
  }

  private func submit() {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    lookUp(text, fieldFrame)
  }

  // MARK: Figures

  private var figures: some View {
    let counts = data.today.counts
    return HStack(spacing: WindowLayout.tileSpacing) {
      StatTile(
        label: WindowStrings.lookedUpToday, value: counts.terms,
        unit: WindowStrings.lookedUpUnit(terms: counts.terms, sentences: counts.translations))
      StatTile(
        label: WindowStrings.wroteToday, value: counts.writes,
        unit: WindowStrings.wroteUnit(count: counts.writes, replaced: counts.replaced))
      StatTile(
        label: WindowStrings.dueLabel, value: data.today.due,
        unit: WindowStrings.dueUnit(data.today.due),
        isEmphasized: true
      ) {
        if data.today.due > 0 {
          PrimaryButton(title: WindowStrings.startReview) { navigation.section = .review }
        }
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(WindowStrings.overview)
  }

  // MARK: Recent

  private var recent: some View {
    VStack(alignment: .leading, spacing: WindowLayout.headingSpacing) {
      SectionHeading(title: WindowStrings.recent) {
        LinkButton(title: WindowStrings.allHistory) { navigation.section = .history }
      }
      WindowCard {
        let lines = data.today.recent.map {
          ActivityLine(
            $0, now: data.now(), timeZone: data.timeZone(), locale: SettingsText.uiLocale)
        }
        if lines.isEmpty {
          EmptyCardText(text: WindowStrings.nothingYet)
        }
        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
          if index > 0 { CardDivider() }
          ActivityRow(line: line) { termID, learning in
            Task { await data.setTier(learning ? .seen : .learning, termID: termID) }
          }
        }
      }
    }
  }

  // MARK: Frequent

  private var frequent: some View {
    VStack(alignment: .leading, spacing: WindowLayout.headingSpacing) {
      SectionHeading(WindowStrings.frequent)
      WindowCard(padding: data.today.frequent.isEmpty ? 0 : WindowLayout.listInset) {
        if data.today.frequent.isEmpty {
          EmptyCardText(text: WindowStrings.nothingFrequent)
        }
        ForEach(data.today.frequent, id: \.id) { term in
          HStack(spacing: Spacing.row) {
            Text(term.lemma)
              .font(WindowType.term.font)
              .foregroundStyle(Color(Palette.textPrimary))
              .lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .leading)
            Pill(WindowStrings.encounters(term.encounterCount))
            CardButton(title: WindowStrings.learn) {
              Task { await data.setTier(.learning, termID: term.id) }
            }
          }
          .padding(WindowLayout.listInset)
        }
      }
    }
  }
}

/// One line of the recent list: word, tag, meaning and sentence, app and time, star.
struct ActivityRow: View {
  let line: ActivityLine
  /// The star: the term and whether it is 要学 now.
  let toggleLearning: (Int64, Bool) -> Void

  var body: some View {
    HStack(spacing: Spacing.pill) {
      Text(line.title)
        .font(WindowType.term.font)
        .foregroundStyle(Color(line.isEvent ? Palette.textQuiet : Palette.textPrimary))
        .lineLimit(1)
        .frame(width: WindowLayout.termWidth, alignment: .leading)
      Color.clear
        .frame(width: WindowLayout.tagWidth, height: 1)
        .overlay {
          if let tag = line.tag {
            Text(tag)
              .font(WindowType.badge.font)
              .foregroundStyle(line.tagTone.onTint)
              .lineLimit(1)
              .frame(width: WindowLayout.tagWidth)
              .padding(.vertical, WindowLayout.tagVertical)
              .background(
                line.tagTone.tint,
                in: RoundedRectangle(cornerRadius: Radius.partOfSpeech, style: .continuous)
              )
              .fixedSize()
          }
        }
      text
        .font(WindowType.row.font)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(line.detail)
        .font(WindowType.detail.font)
        .foregroundStyle(Color(Palette.textSecondary))
        .lineLimit(1)
        .fixedSize()
      // The star's place is kept on a sentence's row, so every row has one height and the
      // details line up.
      Color.clear
        .frame(width: Size.iconButton, height: Size.iconButton)
        .overlay {
          if let termID = line.termID {
            IconButton(
              title: line.isLearning ? WindowStrings.markedToLearn : WindowStrings.markToLearn,
              symbol: line.isLearning ? "star.fill" : "star", isOn: line.isLearning
            ) { toggleLearning(termID, line.isLearning) }
          }
        }
    }
    .padding(.horizontal, WindowLayout.cardRowHorizontal)
    .padding(.vertical, WindowLayout.cardRowVertical)
  }

  private var text: Text {
    let secondary = Color(Palette.textSecondary)
    let primary = Color(Palette.textPrimary)
    switch line.text {
    case .meaning(let meaning, let sentence):
      guard let sentence else { return Text(meaning).foregroundColor(primary) }
      if meaning.isEmpty { return Text(sentence).foregroundColor(secondary) }
      return Text(meaning).foregroundColor(primary)
        + Text(verbatim: " — \(sentence)").foregroundColor(secondary)
    case .result(let result, let source):
      return Text(result).foregroundColor(primary)
        + Text(verbatim: " — \(source)").foregroundColor(secondary)
    case .diff(let segments):
      return segments.reduce(Text(verbatim: "")) { text, segment in
        switch segment {
        case .unchanged(let same):
          return text + Text(same).foregroundColor(primary)
        case .changed(let from, let to):
          var result = text
          if !from.isEmpty {
            result = result + Text(from).foregroundColor(Color(DiffColor.removed)).strikethrough()
          }
          if !from.isEmpty && !to.isEmpty { result = result + Text(verbatim: " ") }
          if !to.isEmpty { result = result + Text(to).foregroundColor(Color(DiffColor.inserted)) }
          return result
        }
      }
    }
  }
}

/// A short line in an empty card.
struct EmptyCardText: View {
  let text: String

  var body: some View {
    Text(text)
      .font(WindowType.row.font)
      .foregroundStyle(Color(Palette.textSecondary))
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, WindowLayout.cardRowHorizontal)
      .padding(.vertical, WindowLayout.cardRowVertical + 2)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
