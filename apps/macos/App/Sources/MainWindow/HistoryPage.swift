// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import SwiftUI

/// 查询记录 (Design/main-app/history.html): every lookup and sentence by day, searchable and
/// filtered by type and app, with the selected entry's card on the right.
///
/// Unlike `PageScaffold`, the list and the detail scroll on their own below a fixed header,
/// so the detail stays in view down a long list; neither reaches under the title bar.
struct HistoryPage: View {
  let data: WindowData
  let services: HistoryServices

  private enum Focus { case search, list }

  @State private var search = ""
  @State private var confirmingDelete: Activity?
  @State private var width: CGFloat = 0
  @FocusState private var focus: Focus?

  private var history: HistoryModel { data.history }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
        .padding(.top, WindowLayout.pageTop)
        .padding(.horizontal, WindowLayout.pageSide)
      filters
        .padding(.top, HistoryLayout.blockSpacing)
        .padding(.horizontal, WindowLayout.pageSide)
      HStack(alignment: .top, spacing: HistoryLayout.columnSpacing) {
        list
        detail
          .frame(width: HistoryLayout.detailWidth(page: width))
      }
      .padding(.top, HistoryLayout.blockSpacing - WindowLayout.shadowRoom)
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      width = $0
    }
    .task(id: data.refreshID) { await history.reload(keepingLoaded: true) }
    // The model outlives the page; the field shows its search when the page comes back.
    .onAppear { search = history.filter.search }
    .onChange(of: search) { _, text in Task { await history.setSearch(text) } }
    .background {
      // ⌘F while this page is shown.
      Button("") { focus = .search }
        .keyboardShortcut("f", modifiers: .command)
        .hidden()
    }
    .alert(
      HistoryStrings.deleteTitle,
      isPresented: Binding(
        get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }),
      presenting: confirmingDelete
    ) { activity in
      Button(HistoryStrings.deleteConfirm, role: .destructive) {
        Task { await history.delete(activity) }
      }
    } message: { activity in
      if case .lookup = activity {
        Text(HistoryStrings.deleteWordMessage)
      } else {
        Text(HistoryStrings.deleteSentenceMessage)
      }
    }
  }

  // MARK: Header

  private var header: some View {
    HStack(alignment: .bottom, spacing: Spacing.input) {
      PageHeader(
        title: MainSection.history.title,
        subtitle: HistoryStrings.counts(
          total: history.counts.total, thisWeek: history.counts.since))
      searchField
        .frame(minWidth: HistoryLayout.searchMinWidth, maxWidth: HistoryLayout.searchMaxWidth)
    }
  }

  private var searchField: some View {
    HStack(spacing: Spacing.row) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: Size.symbol, weight: Size.symbolWeight))
        .foregroundStyle(Color(Palette.textSecondary))
        .accessibilityHidden(true)
      TextField(HistoryStrings.searchPlaceholder, text: $search)
        .textFieldStyle(.plain)
        .font(WindowType.row.font)
        .focused($focus, equals: .search)
        .accessibilityLabel(HistoryStrings.searchLabel)
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
        .onSubmit { focus = .list }
      KeyCap(keys: "⌘F")
        .foregroundStyle(Color(Palette.textSecondary))
    }
    .padding(.horizontal, Spacing.pill)
    .frame(height: HistoryLayout.searchHeight)
    .background(
      Color(Palette.cardFill),
      in: RoundedRectangle(cornerRadius: HistoryLayout.searchRadius, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: HistoryLayout.searchRadius, style: .continuous)
        .strokeBorder(Color(Palette.separator), lineWidth: 0.5)
    )
    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
  }

  // MARK: Filters

  /// The kinds and the app menu on one line, or the menu under the kinds where the line
  /// would be wider than the page, as in English at the smallest width.
  private var filters: some View {
    let kinds = KindPicker(selection: history.filter.kind) { kind in
      Task { await history.setKind(kind) }
    }
    let apps = SourceAppMenu(apps: history.apps, selection: history.filter.sourceApp) { app in
      Task { await history.setSourceApp(app) }
    }
    return ViewThatFits(in: .horizontal) {
      HStack(spacing: Spacing.row) {
        kinds
        Spacer(minLength: 0)
        apps
      }
      VStack(alignment: .leading, spacing: Spacing.pill) {
        kinds
        apps
      }
    }
  }

  // MARK: List

  private var list: some View {
    let sections = HistorySection.group(
      history.items, now: data.now(), timeZone: data.timeZone(), locale: SettingsText.uiLocale)
    return ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if history.hasLoaded && history.items.isEmpty {
            WindowCard { EmptyCardText(text: emptyText) }
          }
          ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
            Text(section.title)
              .font(WindowType.badge.font)
              .foregroundStyle(Color(Palette.textSecondary))
              .padding(.horizontal, HistoryLayout.dayTitleInset)
              .padding(.top, index == 0 ? 0 : HistoryLayout.daySpacing)
              .padding(.bottom, HistoryLayout.dayTitleSpacing)
              .accessibilityAddTraits(.isHeader)
            ForEach(Array(section.lines.enumerated()), id: \.element.id) { row, line in
              HistoryRow(
                line: line, isSelected: line.id == history.selectedID, isFirst: row == 0,
                isLast: row == section.lines.count - 1
              ) {
                history.selectedID = line.id
                focus = .list
              }
              .id(line.id)
            }
          }
          if history.hasMore {
            ProgressView()
              .controlSize(.small)
              .frame(maxWidth: .infinity)
              .padding(.vertical, Spacing.section)
              // A new identity per page, so it asks again while it stays in view.
              .id("more-\(history.items.count)")
              .onAppear { Task { await history.loadMore() } }
          }
        }
        .padding(.top, WindowLayout.shadowRoom)
        .padding(.leading, WindowLayout.pageSide)
        .padding(.bottom, WindowLayout.pageBottom)
      }
      .focusable()
      .focused($focus, equals: .list)
      .focusEffectDisabled()
      .onMoveCommand { direction in
        switch direction {
        case .up: _ = move(-1)
        case .down: _ = move(1)
        default: break
        }
      }
      .onDeleteCommand { confirmingDelete = history.selected }
      .onChange(of: history.selectedID) { _, id in
        guard let id else { return }
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
      }
    }
  }

  private var emptyText: String {
    history.counts.total == 0 ? HistoryStrings.nothingYet : HistoryStrings.noMatches
  }

  private func move(_ offset: Int) -> KeyPress.Result {
    Task { await history.moveSelection(by: offset) }
    return .handled
  }

  // MARK: Detail

  private var detail: some View {
    ScrollView {
      Group {
        if let selected = history.selected {
          HistoryDetail(
            activity: selected, model: history, services: services, timeZone: data.timeZone()
          ) { confirmingDelete = selected }
          .id(selected.historyID)
        } else if !history.items.isEmpty {
          WindowCard { EmptyCardText(text: HistoryStrings.selectSomething) }
        }
      }
      .padding(.top, WindowLayout.shadowRoom)
      .padding(.trailing, WindowLayout.pageSide)
      .padding(.bottom, WindowLayout.pageBottom)
    }
  }
}

/// One entry in the list: two lines on a slice of the day's card.
private struct HistoryRow: View {
  let line: HistoryLine
  let isSelected: Bool
  let isFirst: Bool
  let isLast: Bool
  let select: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.tight) {
      HStack(spacing: Spacing.row) {
        title
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)
        if let tag = line.tag {
          Text(tag)
            .font(WindowType.badge.font)
            .foregroundStyle(line.tagTone.onTint)
            .lineLimit(1)
            .frame(minWidth: WindowLayout.tagWidth)
            .padding(.vertical, WindowLayout.tagVertical)
            .background(
              line.tagTone.tint,
              in: RoundedRectangle(cornerRadius: Radius.partOfSpeech, style: .continuous)
            )
            .fixedSize()
        }
      }
      HStack(spacing: Spacing.row) {
        Text(line.subtitle)
          .font(Typography.secondary.font)
          .foregroundStyle(Color(Palette.textSecondary))
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(line.detail)
          .font(WindowType.detail.font)
          .foregroundStyle(Color(Palette.textSecondary))
          .lineLimit(1)
          .fixedSize()
        if line.termID != nil {
          Image(systemName: line.isLearning ? "star.fill" : "star")
            .font(.system(size: HistoryLayout.starSize, weight: Size.symbolWeight))
            .foregroundStyle(Color(line.isLearning ? Palette.accent : Palette.textTertiary))
            .accessibilityLabel(line.isLearning ? HistoryStrings.learning : HistoryStrings.seen)
        }
      }
    }
    .padding(.vertical, HistoryLayout.rowVertical)
    .padding(.horizontal, WindowLayout.cardRowHorizontal)
    .background { CardSlice(isFirst: isFirst, isLast: isLast, isSelected: isSelected) }
    .contentShape(Rectangle())
    .onTapGesture(perform: select)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityAction(.default, select)
  }

  private var title: Text {
    switch line.title {
    case .word(let word):
      Text(word)
        .font(WindowType.term.font)
        .foregroundColor(Color(Palette.textPrimary))
    case .text(let text):
      Text(text)
        .font(HistoryLayout.sentenceTitle.font)
        .foregroundColor(Color(Palette.textPrimary))
    case .diff(let segments):
      Text(inlineDiff(segments))
        .font(HistoryLayout.sentenceTitle.font)
    }
  }
}

/// A correction on one line: removed words struck through in red, inserted ones in green on
/// their tint, as the panel's diff draws them.
func inlineDiff(_ segments: [DiffSegment]) -> AttributedString {
  var text = AttributedString()
  for segment in segments {
    switch segment {
    case .unchanged(let same):
      var run = AttributedString(same)
      run.foregroundColor = Color(Palette.textPrimary)
      text += run
    case .changed(let from, let to):
      if !from.isEmpty {
        var removed = AttributedString(from)
        removed.foregroundColor = Color(DiffColor.removed)
        removed.strikethroughStyle = .single
        text += removed
      }
      if !from.isEmpty && !to.isEmpty { text += AttributedString(" ") }
      if !to.isEmpty {
        var inserted = AttributedString(to)
        inserted.foregroundColor = Color(DiffColor.inserted)
        inserted.backgroundColor = Color(DiffColor.insertedTint)
        text += inserted
      }
    }
  }
  return text
}

/// A row's part of its day's card: the card's fill and hairline edge, rounded at the top of
/// the first row and the bottom of the last, a line between rows, and the selection's tint
/// with its accent bar. Each row draws its own slice, so the list stays lazy.
private struct CardSlice: View {
  let isFirst: Bool
  let isLast: Bool
  let isSelected: Bool

  var body: some View {
    let radius = WindowLayout.cardRadius
    let shape = UnevenRoundedRectangle(
      topLeadingRadius: isFirst ? radius : 0, bottomLeadingRadius: isLast ? radius : 0,
      bottomTrailingRadius: isLast ? radius : 0, topTrailingRadius: isFirst ? radius : 0,
      style: .continuous)
    ZStack(alignment: .leading) {
      Color(Palette.cardFill)
      if isSelected {
        Color(Palette.accentBlock)
        Color(Palette.accent).frame(width: HistoryLayout.selectionBar)
      }
    }
    .clipShape(shape)
    .overlay(alignment: .bottom) {
      if !isLast { CardDivider() }
    }
    .overlay {
      // The edge drawn a point past the ends that join other rows, then cut there, leaves
      // only the sides of a middle row.
      shape.strokeBorder(Color(Palette.separator), lineWidth: 0.5)
        .padding(.top, isFirst ? 0 : -1)
        .padding(.bottom, isLast ? 0 : -1)
        .clipped()
    }
  }
}

/// 全部 · 单词 · 翻译 · 纠错 · 译成外语, as a segmented control drawn like the mockup's.
private struct KindPicker: View {
  let selection: HistoryKind
  let select: (HistoryKind) -> Void

  var body: some View {
    HStack(spacing: 2) {
      ForEach(HistoryKind.allCases, id: \.self) { kind in
        let isSelected = kind == selection
        Button {
          select(kind)
        } label: {
          Text(HistoryStrings.kind(kind))
            .font((isSelected ? HistoryLayout.segmentSelected : HistoryLayout.segment).font)
            .foregroundStyle(Color(isSelected ? Palette.textPrimary : Palette.textQuiet))
            .lineLimit(1)
            .padding(.horizontal, HistoryLayout.segmentPadding)
            .frame(height: HistoryLayout.segmentHeight)
            .background {
              if isSelected {
                RoundedRectangle(cornerRadius: HistoryLayout.segmentRadius, style: .continuous)
                  .fill(Color(Palette.cardFill))
                  .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
              }
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusRing(
          RoundedRectangle(cornerRadius: HistoryLayout.segmentRadius, style: .continuous)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .padding(2)
    .background(
      Color(Palette.neutralTint),
      in: RoundedRectangle(cornerRadius: HistoryLayout.segmentRadius + 2, style: .continuous)
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel(HistoryStrings.kindLabel)
  }
}

/// 「来源应用：全部 ⌄」: a menu of every app something was recorded in.
private struct SourceAppMenu: View {
  let apps: [String]
  let selection: String?
  let select: (String?) -> Void

  var body: some View {
    Menu {
      Button(HistoryStrings.allApps) { select(nil) }
      if !apps.isEmpty { Divider() }
      ForEach(apps, id: \.self) { app in
        Button(Self.name(app)) { select(app) }
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "macwindow").accessibilityHidden(true)
        Text(HistoryStrings.sourceApp(selection.map(Self.name))).lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.system(size: HistoryLayout.chevronSize, weight: .semibold))
          .accessibilityHidden(true)
      }
      .font(Typography.button.font)
      .foregroundStyle(Color(Palette.textQuiet))
      .padding(.horizontal, Spacing.pill)
      .frame(height: Size.button)
      .background(Color(Palette.neutralTint), in: Capsule())
      .fixedSize()
      .contentShape(Capsule())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .focusRing(Capsule())
  }

  /// The app's name, or its bundle id when it is not installed.
  static func name(_ bundleID: String) -> String {
    ActivityLine.appName(bundleID: bundleID) ?? bundleID
  }
}

/// The History page's measures (Design/main-app/history.html).
enum HistoryLayout {
  /// Between the header, the filters and the columns.
  static let blockSpacing: CGFloat = 20
  static let columnSpacing: CGFloat = 24
  /// The detail takes 1.4 parts of the width to the list's 1, and never less than this.
  static let detailMinWidth: CGFloat = 340
  static let searchHeight: CGFloat = 38
  static let searchRadius: CGFloat = 10
  static let searchMinWidth: CGFloat = 220
  static let searchMaxWidth: CGFloat = 320
  static let segmentHeight: CGFloat = 28
  static let segmentPadding: CGFloat = 14
  static let segmentRadius: CGFloat = 7
  static let segment = TextStyle(size: 13)
  static let segmentSelected = TextStyle(size: 13, weight: .semibold)
  static let chevronSize: CGFloat = 10
  static let daySpacing: CGFloat = 18
  static let dayTitleSpacing: CGFloat = 8
  static let dayTitleInset: CGFloat = 4
  static let rowVertical: CGFloat = 11
  static let selectionBar: CGFloat = 3
  static let starSize: CGFloat = 12
  /// A translated or corrected sentence as a row's title.
  static let sentenceTitle = TextStyle(size: 14, weight: .medium)
  static let detailPadding: CGFloat = 24
  static let detailBottom: CGFloat = 20
  static let deletePadding: CGFloat = 10

  /// The detail's width in a page `page` wide, side margins included.
  static func detailWidth(page: CGFloat) -> CGFloat {
    let columns = page - WindowLayout.pageSide * 2 - columnSpacing
    return max(detailMinWidth, (columns * 1.4 / 2.4).rounded()) + WindowLayout.pageSide
  }
}
