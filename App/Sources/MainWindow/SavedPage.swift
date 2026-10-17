// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import SwiftUI

/// 生词本 (Design/main-app/saved.html): the 要学 words in a table with search, filters and
/// orders, and the selected word's meanings and every sentence it was met in beside it.
struct SavedPage: View {
  let data: WindowData
  let navigation: MainNavigation
  /// Speaks a term in its language.
  let pronounce: (String, Locale.Language, SpeechRate) -> Void

  @State private var search = ""
  @State private var filter = SavedFilter.all
  @State private var sort = SavedSort.lastSeen
  @State private var selectedID: Int64?
  @State private var width: CGFloat = 0

  var body: some View {
    let list = SavedList(now: data.now(), timeZone: data.timeZone())
    let visible = list.visible(data.saved, search: search, filter: filter, sort: sort)
    let selected = visible.first { $0.term.id == selectedID } ?? visible.first
    PageScaffold(
      title: MainSection.saved.title, subtitle: SavedStrings.subtitle,
      titleNote: data.saved.isEmpty ? nil : SavedStrings.words(data.saved.count)
    ) {
      ExportMenu(data: data)
    } content: {
      VStack(alignment: .leading, spacing: WindowLayout.savedSpacing) {
        toolbar(counts: list.counts(data.saved))
        if data.saved.isEmpty {
          WindowCard { EmptyCardText(text: SavedStrings.nothingSaved) }
        } else {
          let table = SavedTable(
            terms: visible, total: data.saved.count, selectedID: selected?.term.id,
            list: list, context: context,
            select: { selectedID = $0 },
            stopLearning: stopLearning)
          let detail = selected.map {
            SavedDetail(
              term: $0, list: list, context: context,
              reviewNow: navigation.startReview(with:),
              openHistory: { navigation.section = .history },
              pronounce: pronounce, stopLearning: stopLearning)
          }
          if isWide {
            HStack(alignment: .top, spacing: WindowLayout.savedColumnSpacing) {
              table.layoutPriority(1)
              detail.frame(width: WindowLayout.savedDetailWidth)
            }
          } else {
            VStack(alignment: .leading, spacing: WindowLayout.savedColumnSpacing) {
              table
              detail
            }
          }
        }
      }
      .onGeometryChange(for: CGFloat.self) {
        $0.size.width
      } action: {
        width = $0
      }
    }
  }

  /// The table and the details side by side, else the details under the table, as the
  /// mockup's columns wrap.
  private var isWide: Bool {
    width
      >= WindowLayout.savedTableMinWidth + WindowLayout.savedColumnSpacing
      + WindowLayout.savedDetailWidth
  }

  private var context: SavedRowContext {
    SavedRowContext(now: data.now(), timeZone: data.timeZone(), locale: SettingsText.uiLocale)
  }

  private func stopLearning(_ termID: Int64) {
    Task { await data.setTier(.seen, termID: termID) }
  }

  // MARK: Toolbar

  /// The search field, filters and order on one line, or the filters and the order under
  /// the field where the line would be wider than the page.
  private func toolbar(counts: [SavedFilter: Int]) -> some View {
    let filters = FilterBar(selection: $filter, counts: counts)
    let sortMenu = SortMenu(selection: $sort)
    return ViewThatFits(in: .horizontal) {
      HStack(spacing: Spacing.pill) {
        searchField
        filters
        sortMenu
      }
      VStack(alignment: .leading, spacing: Spacing.pill) {
        searchField
        HStack(spacing: Spacing.pill) {
          filters
          Spacer(minLength: 0)
          sortMenu
        }
      }
    }
  }

  private var searchField: some View {
    HStack(spacing: Spacing.row) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: Size.symbol, weight: Size.symbolWeight))
        .foregroundStyle(Color(Palette.textSecondary))
        .accessibilityHidden(true)
      TextField(SavedStrings.searchPlaceholder, text: $search)
        .textFieldStyle(.plain)
        .font(WindowType.row.font)
        .accessibilityLabel(SavedStrings.searchLabel)
    }
    .padding(.horizontal, Spacing.pill)
    .frame(height: WindowLayout.savedControlHeight)
    .frame(minWidth: WindowLayout.savedSearchMinWidth, maxWidth: .infinity)
    .background(
      Color(Palette.cardFill),
      in: RoundedRectangle(cornerRadius: WindowLayout.savedFieldRadius, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: WindowLayout.savedFieldRadius, style: .continuous)
        .strokeBorder(Color(Palette.separator), lineWidth: 0.5)
    )
  }
}

// MARK: - Tokens

extension WindowLayout {
  /// Between the toolbar and the table.
  static let savedSpacing: CGFloat = 20
  static let savedColumnSpacing: CGFloat = 24
  static let savedDetailWidth: CGFloat = 300
  /// Below this the table scrolls sideways.
  static let savedTableMinWidth: CGFloat = 600
  static let savedControlHeight: CGFloat = 36
  static let savedSearchMinWidth: CGFloat = 220
  static let savedFieldRadius: CGFloat = 10
  /// The table's fixed columns (Design/main-app/saved.html); the meaning takes the rest.
  static let savedWordColumn: CGFloat = 124
  static let savedSeenColumn: CGFloat = 88
  static let savedLastSeenColumn: CGFloat = 120
  static let savedReviewColumn: CGFloat = 96
  static let savedStarColumn: CGFloat = 40
  static let savedCellHorizontal: CGFloat = 12
  static let savedCellVertical: CGFloat = 11
  static let savedHeaderVertical: CGFloat = 10
  /// The accent bar at the selected row's leading edge.
  static let savedSelectionBar: CGFloat = 3
  /// The filters' track and its buttons.
  static let segmentHeight: CGFloat = 26
  static let segmentInset: CGFloat = 3
  static let segmentRadius: CGFloat = 6
  static let segmentPadding: CGFloat = 12
}

extension WindowType {
  /// A table's column header.
  static let columnHeader = TextStyle(size: 12, weight: .semibold)
  static let segment = TextStyle(size: 13)
  static let segmentSelected = TextStyle(size: 13, weight: .semibold)
  /// The headword of the detail pane's word.
  static let savedMeaning = TextStyle(size: 14.5, lineSpacing: 4)
  static let savedPhonetic = TextStyle(size: 12)
  static let outlineButton = TextStyle(size: 13.5, weight: .semibold)
}

extension Palette {
  /// The filters' track, and the selected filter on it.
  static let segmentTrack = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(white: 1, alpha: 0.07)
      : NSColor(srgbRed: 0xEB / 255, green: 0xEB / 255, blue: 0xEF / 255, alpha: 1)
  }
  static let segmentSelected = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(white: 1, alpha: 0.16) : .white
  }
}

// MARK: - Toolbar pieces

/// 「全部 · 待复习 9 · 本周新加 · 已熟悉」 on a track, the selected one raised.
private struct FilterBar: View {
  @Binding var selection: SavedFilter
  let counts: [SavedFilter: Int]

  var body: some View {
    HStack(spacing: 2) {
      ForEach(SavedFilter.allCases, id: \.self) { filter in
        let isSelected = filter == selection
        Button {
          selection = filter
        } label: {
          HStack(spacing: 4) {
            Text(SavedStrings.title(filter))
              .font((isSelected ? WindowType.segmentSelected : WindowType.segment).font)
              .foregroundStyle(Color(isSelected ? Palette.textPrimary : Palette.textQuiet))
            if filter != .all, let count = counts[filter] {
              Text(count, format: .number)
                .font(WindowType.segmentSelected.font)
                .foregroundStyle(
                  Color(filter == .due && count > 0 ? Palette.accent : Palette.textSecondary))
            }
          }
          .lineLimit(1)
          .padding(.horizontal, WindowLayout.segmentPadding)
          .frame(height: WindowLayout.segmentHeight)
          .background {
            if isSelected {
              RoundedRectangle(cornerRadius: WindowLayout.segmentRadius, style: .continuous)
                .fill(Color(Palette.segmentSelected))
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                .overlay(
                  RoundedRectangle(cornerRadius: WindowLayout.segmentRadius, style: .continuous)
                    .strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
            }
          }
          .contentShape(Rectangle())
          .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .padding(WindowLayout.segmentInset)
    .background(
      Color(Palette.segmentTrack),
      in: RoundedRectangle(
        cornerRadius: WindowLayout.segmentRadius + WindowLayout.segmentInset, style: .continuous)
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel(SavedStrings.filterLabel)
  }
}

/// 「⇅ 排序 最近遇到 ⌄」.
private struct SortMenu: View {
  @Binding var selection: SavedSort

  var body: some View {
    Menu {
      Picker(SavedStrings.sort, selection: $selection) {
        ForEach(SavedSort.allCases, id: \.self) { sort in
          Text(SavedStrings.title(sort)).tag(sort)
        }
      }
      .pickerStyle(.inline)
      .labelsHidden()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "arrow.up.arrow.down")
          .font(.system(size: Size.symbol - 2, weight: .regular))
          .accessibilityHidden(true)
        Text(SavedStrings.sort).foregroundStyle(Color(Palette.textSecondary))
        Text(SavedStrings.title(selection))
        Image(systemName: "chevron.down")
          .font(.system(size: 10, weight: .semibold))
          .accessibilityHidden(true)
      }
      .font(WindowType.segment.font)
      .foregroundStyle(Color(Palette.textQuiet))
      .padding(.horizontal, Spacing.row)
      .frame(height: Size.button)
      .contentShape(Rectangle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
  }
}

/// 「导出 CSV、Anki ⌄」: either file, saved where the user says.
private struct ExportMenu: View {
  let data: WindowData

  var body: some View {
    Menu {
      Button(SavedStrings.exportCSV) { SavedExport.csv.save(from: data) }
      Button(SavedStrings.exportAnki) { SavedExport.anki.save(from: data) }
    } label: {
      OutlineLabel {
        Image(systemName: "square.and.arrow.down")
          .accessibilityHidden(true)
        Text(SavedStrings.export)
        Text(SavedStrings.exportFormats)
          .fontWeight(.regular)
          .foregroundStyle(Color(Palette.textSecondary))
        Image(systemName: "chevron.down")
          .font(.system(size: 10, weight: .semibold))
          .accessibilityHidden(true)
      }
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .accessibilityLabel(SavedStrings.exportLabel)
  }
}

/// A white capsule with a hairline edge, as the mockup's export menu and secondary actions.
struct OutlineLabel<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    HStack(spacing: 6) { content }
      .font(WindowType.outlineButton.font)
      .foregroundStyle(Color(Palette.textQuiet))
      .lineLimit(1)
      .padding(.horizontal, 14)
      .frame(height: Size.button)
      .background(Color(Palette.cardFill), in: Capsule())
      .overlay(Capsule().strokeBorder(Color(Palette.separator), lineWidth: 0.5))
      .fixedSize()
      .contentShape(Capsule())
  }
}

/// The two exports of 生词本, each asked for with a save panel on the main window.
enum SavedExport {
  case csv, anki

  @MainActor
  func save(from data: WindowData) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "\(MainSection.saved.title).\(self == .csv ? "csv" : "txt")"
    panel.allowedContentTypes = [self == .csv ? .commaSeparatedText : .tabSeparatedText]
    let write: (URL) -> Void = { url in
      Task { @MainActor in
        do {
          let file = try await (self == .csv ? data.exportSavedCSV() : data.exportAnki())
          try file?.write(to: url, options: .atomic)
        } catch {
          Log.store.error("export failed: \(String(describing: error), privacy: .public)")
          let alert = NSAlert()
          alert.messageText = SettingsText.exportFailed
          alert.informativeText = error.localizedDescription
          alert.runModal()
        }
      }
    }
    let completion = { (response: NSApplication.ModalResponse) in
      if response == .OK, let url = panel.url { write(url) }
    }
    if let window = NSApp.keyWindow {
      panel.beginSheetModal(for: window, completionHandler: completion)
    } else {
      panel.begin(completionHandler: completion)
    }
  }
}
