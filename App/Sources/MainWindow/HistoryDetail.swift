// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import SwiftUI

/// What the History page needs from the rest of the app: the dictionary, speech, the
/// pasteboard and the browser. The app delegate fills it in; the defaults do nothing, so the
/// gallery and the tests never speak, copy or open anything.
@MainActor
struct HistoryServices {
  /// The dictionary layer of a term met in a sentence, as the panel's card uses it.
  var lookUpTerm: (String, String?) async -> [LexiconEntry] = { _, _ in [] }
  var accent: () -> Accent = { .american }
  var pronounce: (String, Locale.Language, SpeechRate) -> Void = { _, _, _ in }
  var copy: (String) -> Void = { _ in }
  var openURL: (URL) -> Void = { _ in }
}

extension CardState {
  /// The card of one recorded lookup: the dictionary layer, the term's stored model card,
  /// and this encounter's sentence, meaning and translation. The stored card is the term's
  /// latest, made for its latest sentence, so its meaning only stands in when the encounter
  /// has none, and its sentence translation is never shown under another sentence.
  init(lookup: DailyLog.Lookup, entry: LexiconEntry?, accent: Accent) {
    let encounter = lookup.encounter
    let stored = lookup.term.card.flatMap { try? decodeCard($0.json) }
    self.init(
      term: encounter.surface, context: encounter.sentence, entry: entry, accent: accent,
      model: stored == nil ? .unavailable : .complete)
    if let stored { show(stored) }
    lemma = lookup.term.lemma
    if let sense = encounter.sense, !sense.isEmpty { definition = sense }
    contextTranslation = encounter.sentenceTranslation
    encounters = lookup.term.encounterCount
    isLearning = lookup.term.tier == .learning
  }
}

/// The right-hand pane: the selected entry in a card, with its source and actions.
struct HistoryDetail: View {
  let activity: Activity
  let model: HistoryModel
  let services: HistoryServices
  let timeZone: TimeZone
  let requestDelete: () -> Void

  var body: some View {
    WindowCard(padding: 0) {
      VStack(alignment: .leading, spacing: Spacing.section) {
        switch activity {
        case .lookup(let lookup):
          LookupDetail(lookup: lookup, model: model, services: services, timeZone: timeZone)
        case .sentence(let event):
          SentenceDetail(event: event, services: services, timeZone: timeZone)
        }
        // On a line of its own for every kind, away from the actions, so it never wraps
        // under them on its own.
        CardDivider()
        DeleteButton(action: requestDelete)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .padding(.top, HistoryLayout.detailPadding)
      .padding(.horizontal, HistoryLayout.detailPadding)
      .padding(.bottom, HistoryLayout.detailBottom)
    }
  }
}

/// A word: the panel's card from the stored one, then where it was met and the actions.
private struct LookupDetail: View {
  let lookup: DailyLog.Lookup
  let model: HistoryModel
  let services: HistoryServices
  let timeZone: TimeZone

  /// The dictionary entry of the encounter it was looked up for.
  @State private var entry: (id: Int64, entry: LexiconEntry?)?
  @State private var pace = PronunciationPace()

  var body: some View {
    let encounter = lookup.encounter
    let card = CardState(
      lookup: lookup, entry: entry?.id == encounter.id ? entry?.entry : nil,
      accent: services.accent())
    let surface = encounter.surface
    let showsSurface = normalizedKey(surface) != normalizedKey(lookup.term.lemma)
    CardView(
      card: card, showsStar: false, note: showsSurface ? HistoryStrings.surface(surface) : nil
    )
    .task(id: encounter.id) {
      let found = await services.lookUpTerm(surface, encounter.sentence).first
      entry = (encounter.id, found)
    }
    CardDivider()
    SourceSection(
      app: encounter.sourceApp, url: encounter.sourceURL, date: encounter.seenAt,
      timeZone: timeZone, encounters: lookup.term.encounterCount, openURL: services.openURL)
    FlowLayout(spacing: Spacing.buttons) {
      if card.isLearning {
        PrimaryButton(title: HistoryStrings.learn, symbol: "star.fill") { toggle() }
      } else {
        SecondaryButton(title: HistoryStrings.learn, symbol: "star") { toggle() }
      }
      SecondaryButton(title: HistoryStrings.pronounce, symbol: "speaker.wave.2") {
        services.pronounce(
          card.lemma, Locale.Language(identifier: lookup.term.language),
          pace.next(at: ContinuousClock.now))
      }
      SecondaryButton(title: HistoryStrings.copy, symbol: "doc.on.doc") {
        services.copy(card.copyableText)
      }
      if let url = encounter.sourceURL {
        SecondaryButton(title: HistoryStrings.openSource, symbol: "arrow.up.right.square") {
          services.openURL(url)
        }
      }
    }
    .padding(.top, Spacing.tight)
  }

  private func toggle() {
    Task { await model.toggleLearning(lookup) }
  }
}

/// A translation, correction or rewrite: its kind, the text before and after, or the
/// changes in place, then where it was done and the actions.
private struct SentenceDetail: View {
  let event: SentenceEvent
  let services: HistoryServices
  let timeZone: TimeZone

  var body: some View {
    let line = HistoryLine(.sentence(event), timeZone: timeZone, locale: SettingsText.uiLocale)
    HStack(spacing: Spacing.buttons) {
      Pill(HistoryStrings.tag(event.kind), tone: line.tagTone)
      if event.kind != .translated {
        Pill(
          event.applied ? HistoryStrings.replaced : HistoryStrings.notReplaced,
          symbol: event.applied ? "checkmark" : nil, tone: event.applied ? .success : .neutral)
      }
    }
    switch event.kind {
    case .corrected, .improved:
      let segments = textDiff(event.source, event.result)
      SelectableText(
        text: event.result, attributed: diffText(segments),
        font: Typography.proofread.nsFont, lineSpacing: Typography.proofread.lineSpacing,
        accessibilityLabel: HistoryStrings.result)
      Text(HistoryLine.correctionSummary(segments, applied: event.applied))
        .font(Typography.note.font)
        .foregroundStyle(Color(Palette.textSecondary))
    case .translated, .translatedOut:
      LabeledText(label: HistoryStrings.original) {
        SelectableText(
          text: event.source, font: Typography.callout.nsFont, color: Palette.textSecondary,
          lineSpacing: Typography.callout.lineSpacing, accessibilityLabel: HistoryStrings.original)
      }
      LabeledText(label: HistoryStrings.result) {
        SelectableText(
          text: event.result, font: Typography.result.nsFont, color: Palette.textPrimary,
          lineSpacing: Typography.result.lineSpacing, accessibilityLabel: HistoryStrings.result)
      }
    }
    CardDivider()
    SourceSection(
      app: event.sourceApp, url: nil, date: event.createdAt, timeZone: timeZone,
      encounters: nil, openURL: services.openURL)
    FlowLayout(spacing: Spacing.buttons) {
      SecondaryButton(title: HistoryStrings.copy, symbol: "doc.on.doc") {
        services.copy(event.result)
      }
    }
    .padding(.top, Spacing.tight)
  }
}

/// A small heading over its content: 「原文」, 「结果」.
private struct LabeledText<Content: View>: View {
  let label: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.minorRows) {
      Text(label)
        .font(Typography.label.font)
        .foregroundStyle(Color(Palette.textSecondary))
      content
    }
  }
}

/// 「来源」: the app, the page's site as a link, the time and how often the word was met.
private struct SourceSection: View {
  let app: String?
  let url: URL?
  let date: Date
  let timeZone: TimeZone
  let encounters: Int?
  let openURL: (URL) -> Void

  var body: some View {
    LabeledText(label: HistoryStrings.source) {
      FlowLayout(spacing: Spacing.minorRows) {
        let parts = items
        ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
          if index > 0 {
            Text(verbatim: "·")
              .foregroundStyle(Color(Palette.textTertiary))
              .accessibilityHidden(true)
          }
          part
        }
      }
      .font(Typography.secondary.font)
      .foregroundStyle(Color(Palette.textQuiet))
    }
  }

  private var items: [AnyView] {
    var parts: [AnyView] = []
    if let name = app.flatMap({ ActivityLine.appName(bundleID: $0) }) {
      parts.append(AnyView(Text(name)))
    }
    if let url, let host = url.host() {
      let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
      parts.append(
        AnyView(
          Button(site) { openURL(url) }
            .buttonStyle(.plain)
            .focusRing(
              RoundedRectangle(cornerRadius: Radius.partOfSpeech, style: .continuous))
            .foregroundStyle(Color(Palette.accent))
            .help(url.absoluteString)))
    }
    parts.append(
      AnyView(
        Text(
          date.formatted(
            Date.FormatStyle(locale: SettingsText.uiLocale, timeZone: timeZone)
              .month(.abbreviated).day().hour().minute()))))
    if let encounters {
      parts.append(AnyView(Pill(HistoryStrings.encounters(encounters), size: .small)))
    }
    return parts
  }
}

/// 「删除这条记录」: red text on no fill.
private struct DeleteButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "trash").accessibilityHidden(true)
        Text(HistoryStrings.delete).lineLimit(1)
      }
      .font(Typography.button.font)
      .foregroundStyle(Color(Palette.dangerOnTint))
      .padding(.horizontal, HistoryLayout.deletePadding)
      .frame(height: Size.button)
      .fixedSize()
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .focusRing(Capsule())
  }
}

/// Lays its views out in rows like words, wrapping when a row is full.
struct FlowLayout: Layout {
  var spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = rows(for: subviews, width: proposal.width ?? .infinity)
    let width = rows.map(\.width).max() ?? 0
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    return CGSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var y = bounds.minY
    for row in rows(for: subviews, width: bounds.width) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(
          at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
    var rows: [Row] = []
    var row = Row()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
      if needed > width, !row.indices.isEmpty {
        rows.append(row)
        row = Row()
      }
      row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
      row.height = max(row.height, size.height)
      row.indices.append(index)
    }
    if !row.indices.isEmpty { rows.append(row) }
    return rows
  }
}
