// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import SwiftUI

/// The selected word beside 生词本's table: its meanings, every sentence it was met in, and
/// 现在复习, 发音 and 取消要学.
struct SavedDetail: View {
  let term: SavedTerm
  let list: SavedList
  let context: SavedRowContext
  let reviewNow: (Int64) -> Void
  let openHistory: () -> Void
  let pronounce: (String, Locale.Language, SpeechRate) -> Void
  let stopLearning: (Int64) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: WindowLayout.detailSpacing) {
      heading
      meanings
      encounters
      actions
    }
    .padding(.top, WindowLayout.detailPadding)
    .padding(.horizontal, WindowLayout.detailPadding)
    .padding(.bottom, WindowLayout.detailPadding - 2)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(Palette.cardFill),
      in: RoundedRectangle(cornerRadius: WindowLayout.cardRadius, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: WindowLayout.cardRadius, style: .continuous)
        .strokeBorder(Color(Palette.separator), lineWidth: 0.5)
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel(SavedStrings.detailLabel)
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.row) {
        Text(term.term.lemma)
          .font(Typography.headword.font)
          .tracking(Typography.headword.tracking)
          .foregroundStyle(Color(Palette.textPrimary))
          .accessibilityAddTraits(.isHeader)
        if let phonetic = term.card?.phonetic, !phonetic.isEmpty {
          Text(phonetic)
            .font(Typography.callout.font)
            .foregroundStyle(Color(Palette.textSecondary))
        }
      }
      .fixedSize(horizontal: false, vertical: true)
      // The dates after the pills when they fit, else under them.
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 6) {
          pills
          datesText
        }
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 6) { pills }
          datesText
        }
      }
    }
  }

  @ViewBuilder
  private var pills: some View {
    TablePill(text: WindowStrings.encounters(term.term.encounterCount))
    if list.isDue(term) {
      TablePill(text: SavedStrings.dueTag, isFilled: true)
    } else if term.isFamiliar {
      TablePill(text: SavedStrings.familiar, tone: .success)
    }
  }

  private var datesText: some View {
    Text(dates)
      .font(WindowType.detail.font)
      .foregroundStyle(Color(Palette.textSecondary))
      .fixedSize()
  }

  /// 「10 月 9 日加入」, after the next review's day when it is not due.
  private var dates: String {
    var parts: [String] = []
    if !list.isDue(term), let due = term.dueDay {
      parts.append(SavedStrings.reviewOn(SavedStrings.day(due, locale: context.locale)))
    }
    if let added = term.learningDay {
      parts.append(SavedStrings.added(SavedStrings.day(added, locale: context.locale)))
    }
    return parts.joined(separator: " · ")
  }

  @ViewBuilder
  private var meanings: some View {
    let others = (term.card?.otherSenses ?? []).map { sense in
      [CardStrings.partOfSpeech(sense.partOfSpeech), sense.definition]
        .filter { !$0.isEmpty }.joined(separator: " ")
    }
    if !term.meaning.isEmpty || !others.isEmpty {
      VStack(alignment: .leading, spacing: Spacing.buttons) {
        if !term.meaning.isEmpty {
          HStack(alignment: .firstTextBaseline, spacing: Spacing.buttons) {
            if let pos = term.card?.partOfSpeech, !pos.isEmpty {
              PartOfSpeechTag(name: pos)
            }
            Text(term.meaning)
              .font(WindowType.savedMeaning.font)
              .lineSpacing(WindowType.savedMeaning.lineSpacing)
              .foregroundStyle(Color(Palette.textPrimary))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        if !others.isEmpty {
          Text(SavedStrings.otherSenses(others.joined(separator: "；")))
            .font(Typography.secondary.font)
            .lineSpacing(Typography.secondary.lineSpacing)
            .foregroundStyle(Color(Palette.textQuiet))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, WindowLayout.detailBlockVertical)
      .padding(.horizontal, WindowLayout.detailBlockHorizontal)
      .background(
        Color(Palette.accentBlock),
        in: RoundedRectangle(cornerRadius: Radius.block, style: .continuous))
    }
  }

  private var encounters: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(SavedStrings.metHeading)
        .font(Typography.button.font)
        .foregroundStyle(Color(Palette.textQuiet))
        .accessibilityAddTraits(.isHeader)
        .padding(.bottom, 2)
      ForEach(Array(term.encounters.enumerated()), id: \.element.id) { index, encounter in
        VStack(alignment: .leading, spacing: 4) {
          if let sentence = encounter.sentence {
            Text(Self.marked(sentence, encounter: encounter))
              .font(Typography.callout.font)
              .lineSpacing(Typography.callout.lineSpacing)
              .foregroundStyle(Color(Palette.textPrimary))
          } else {
            Text(SavedStrings.noSentence)
              .font(Typography.callout.font)
              .foregroundStyle(Color(Palette.textSecondary))
          }
          if let translation = encounter.sentenceTranslation, !translation.isEmpty {
            Text(translation)
              .font(Typography.secondary.font)
              .lineSpacing(Typography.secondary.lineSpacing)
              .foregroundStyle(Color(Palette.textQuiet))
          }
          Text(context.seen(encounter, withTime: true))
            .font(WindowType.detail.font)
            .foregroundStyle(Color(Palette.textSecondary))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, WindowLayout.cardRowVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
          if index < term.encounters.count - 1 { CardDivider() }
        }
        .accessibilityElement(children: .combine)
      }
      LinkButton(title: SavedStrings.openHistory, action: openHistory)
    }
  }

  private var actions: some View {
    VStack(alignment: .leading, spacing: 0) {
      CardDivider()
      // On one line when they fit, else 现在复习 above the other two.
      ViewThatFits(in: .horizontal) {
        HStack(spacing: Spacing.buttons) {
          reviewButton
          secondaryButtons
        }
        VStack(alignment: .leading, spacing: Spacing.buttons) {
          reviewButton
          HStack(spacing: Spacing.buttons) { secondaryButtons }
        }
      }
      .padding(.top, WindowLayout.detailActionsTop)
    }
  }

  private var reviewButton: some View {
    PrimaryButton(title: SavedStrings.reviewNow) { reviewNow(term.term.id) }
  }

  @ViewBuilder
  private var secondaryButtons: some View {
    Button {
      pronounce(term.term.lemma, Locale.Language(identifier: term.term.language), .normal)
    } label: {
      OutlineLabel {
        Image(systemName: "speaker.wave.2")
          .font(.system(size: Size.symbol - 1, weight: .regular))
          .accessibilityHidden(true)
        Text(SavedStrings.pronounce)
      }
    }
    .buttonStyle(.plain)
    Button {
      stopLearning(term.term.id)
    } label: {
      OutlineLabel { Text(SavedStrings.stopLearningButton) }
    }
    .buttonStyle(.plain)
  }

  /// The sentence with the word on the highlight, by its recorded range or else by the
  /// first whole-word match of the surface.
  static func marked(_ sentence: String, encounter: Encounter) -> AttributedString {
    let units = sentence.utf16
    guard let start = encounter.termStart, let length = encounter.termLength, start >= 0,
      length > 0, start + length <= units.count,
      let lower = units.index(units.startIndex, offsetBy: start, limitedBy: units.endIndex)
        .flatMap({ String.Index($0, within: sentence) }),
      let upper = String.Index(units.index(lower, offsetBy: length), within: sentence)
    else { return CardLayout.marking(encounter.surface, in: sentence) }
    var marked = AttributedString(sentence)
    if let from = AttributedString.Index(lower, within: marked),
      let to = AttributedString.Index(upper, within: marked)
    {
      marked[from..<to].backgroundColor = Color(Palette.highlight)
    }
    return marked
  }
}

extension WindowLayout {
  /// The detail pane: between its blocks, around it, its meaning block and its buttons.
  static let detailSpacing: CGFloat = 18
  static let detailPadding: CGFloat = 22
  static let detailBlockVertical: CGFloat = 14
  static let detailBlockHorizontal: CGFloat = 16
  static let detailActionsTop: CGFloat = 16
}
