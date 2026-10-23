// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import SwiftUI

/// The word card in the panel (architecture 6.6): the word, then the main senses, the
/// dictionary's or else the model's, then the meaning in this sentence and the model's other
/// fields as they arrive. Pronouncing and translating are in the bar (`ActionBar`).
struct CardView: View {
  let card: CardState
  /// The star at the header's trailing edge; History has its 要学 button below the card.
  var showsStar = true
  /// After the word on its baseline: History's 「原文 ran」.
  var note: String?
  var onAction: (PanelAction.ID) -> Void = { _ in }

  var body: some View {
    let main = card.mainSenses
    // One chip width for every part of speech on the card, so the senses and the other
    // meanings share one left edge.
    let chip = CardLayout.chipWidth(
      main.map(\.partOfSpeech) + card.otherSenses.map(\.partOfSpeech))
    VStack(alignment: .leading, spacing: Spacing.section) {
      header
      if !main.isEmpty {
        VStack(alignment: .leading, spacing: Spacing.senses) {
          ForEach(Array(main.enumerated()), id: \.offset) { _, sense in
            SenseRow(
              partOfSpeech: sense.partOfSpeech, text: sense.gloss, chip: chip,
              style: Typography.body)
          }
        }
      } else if card.model == .loading {
        ProgressLine(text: CardStrings.lookingUp, height: Typography.body.lineHeight)
      }
      if card.showsSentenceSection {
        inThisSentence(isWaitingAbove: main.isEmpty)
      }
      if !card.otherSenses.isEmpty {
        CardSection(title: CardStrings.otherSenses, spacing: Spacing.minorRows) {
          ForEach(Array(card.otherSenses.enumerated()), id: \.offset) { _, sense in
            SenseRow(
              partOfSpeech: sense.partOfSpeech, text: sense.definition, chip: chip,
              style: Typography.callout)
          }
        }
      }
      if !card.examples.isEmpty {
        CardSection(title: CardStrings.examples, spacing: Spacing.minorRows) {
          ForEach(Array(card.examples.enumerated()), id: \.offset) { _, example in
            VStack(alignment: .leading, spacing: Spacing.pair) {
              Wrapped(example.sentence, style: Typography.callout)
              Wrapped(
                example.translation, style: Typography.secondary, color: Palette.textSecondary)
            }
          }
        }
      }
      if !card.collocations.isEmpty {
        let column = CardLayout.phraseWidth(card.collocations.map(\.phrase))
        CardSection(title: CardStrings.collocations, spacing: Spacing.tight) {
          ForEach(Array(card.collocations.enumerated()), id: \.offset) { _, collocation in
            HStack(alignment: .firstTextBaseline, spacing: Spacing.pill) {
              Text(collocation.phrase)
                .font(Typography.phrase.font)
                .foregroundStyle(Color(Palette.textPrimary))
                .frame(width: column, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
              Wrapped(
                collocation.meaning, style: Typography.secondary, color: Palette.textSecondary)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: Header

  /// The word over its pronunciation and band, with the star at the trailing edge.
  private var header: some View {
    HStack(alignment: .top, spacing: Spacing.pill) {
      VStack(alignment: .leading, spacing: Spacing.senses) {
        if let note {
          HStack(alignment: .firstTextBaseline, spacing: Spacing.row) {
            lemma
            Text(note)
              .font(Typography.secondary.font)
              .foregroundStyle(Color(Palette.textSecondary))
              .lineLimit(1)
          }
        } else {
          lemma
        }
        details
      }
      Spacer(minLength: 0)
      if showsStar {
        IconButton(
          title: card.isLearning ? CardStrings.learning : CardStrings.learn,
          symbol: card.isLearning ? "star.fill" : "star", shortcut: "⌘S", isOn: card.isLearning
        ) { onAction(CardStrings.learnAction) }
      }
    }
  }

  /// The word on one line, smaller if it must be; a word too long even for that wraps rather
  /// than being cut short.
  private var lemma: some View {
    ViewThatFits(in: .horizontal) {
      headword(Typography.headword).fixedSize()
      headword(Typography.compactHeadword).fixedSize()
      headword(Typography.compactHeadword)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func headword(_ style: TextStyle) -> some View {
    Text(card.lemma)
      .font(style.font)
      .tracking(style.tracking)
      .foregroundStyle(Color(Palette.textPrimary))
  }

  /// The pronunciation after its US or UK tag, and the band; the band goes under a
  /// pronunciation too long to share its line.
  @ViewBuilder private var details: some View {
    if card.phonetic != nil || card.band != nil {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: Spacing.senses) {
          pronunciation.fixedSize()
          band
        }
        VStack(alignment: .leading, spacing: Spacing.tight) {
          pronunciation.fixedSize(horizontal: false, vertical: true)
          band
        }
      }
    }
  }

  @ViewBuilder private var pronunciation: some View {
    if let phonetic = card.phonetic {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.tight) {
        if let transcription = card.transcription {
          Text(verbatim: transcription == .us ? "US" : "UK")
            .font(Typography.tag.font)
            .foregroundStyle(Tone.neutral.onTint)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
              Tone.neutral.tint,
              in: RoundedRectangle(cornerRadius: Radius.tag, style: .continuous))
        }
        Text(phonetic)
          .font(Typography.secondary.font)
          .foregroundStyle(Color(Palette.textSecondary))
      }
    }
  }

  @ViewBuilder private var band: some View {
    if let band = card.band {
      Pill(CardStrings.band(band), tone: band.tone, size: .small)
    }
  }

  // MARK: In this sentence

  /// The meaning in this sentence, the sentence with the word marked, and its translation, on
  /// the accent block. `isWaitingAbove`: the spinner above already says the model is busy.
  private func inThisSentence(isWaitingAbove: Bool) -> some View {
    // With the dictionary the block leads with the model's meaning, a spinner until it comes.
    let waitsForMeaning = !card.senses.isEmpty && card.sentenceMeaning == nil
    let isBusy = card.model == .loading && !waitsForMeaning && !isWaitingAbove
    return TintedBlock {
      HStack(spacing: Spacing.tight) {
        Image(systemName: "sparkles").accessibilityHidden(true)
        Text(CardStrings.inThisSentence)
        if isBusy {
          Spinner(size: Typography.label.size)
            .accessibilityLabel(CardStrings.lookingUp)
        }
      }
      .font(Typography.label.font)
      .foregroundStyle(Tone.accent.onTint)
      if let meaning = card.sentenceMeaning {
        Wrapped(meaning, style: Typography.title)
      } else if waitsForMeaning {
        // The meaning's height, so the block keeps it when the meaning replaces the line.
        ProgressLine(text: CardStrings.lookingUp, height: Typography.title.lineHeight)
      }
      if card.context != nil || card.contextTranslation != nil {
        VStack(alignment: .leading, spacing: Spacing.pair) {
          if let context = card.context {
            Text(CardLayout.marking(card.term, in: context))
              .font(Typography.secondary.font)
              .lineSpacing(Typography.secondary.lineSpacing)
              .foregroundStyle(Color(Palette.textPrimary))
              .frame(maxWidth: .infinity, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
          }
          if let translation = card.contextTranslation {
            Wrapped(translation, style: Typography.secondary, color: Palette.textSecondary)
          }
        }
      }
    }
  }
}

/// The measures of the card that depend on its text.
enum CardLayout {
  static var partOfSpeechFont: NSFont { Typography.partOfSpeech.nsFont }
  /// The narrowest a part-of-speech chip gets, and its label's room on either side.
  static let minimumChipWidth: CGFloat = 44
  static let chipPadding: CGFloat = 6
  /// The widest the collocations' phrase column gets; a longer phrase wraps.
  static let maximumPhraseWidth: CGFloat = 160

  /// The widest label among the parts of speech `names`, 0 for none.
  static func partOfSpeechWidth(_ names: [String]) -> CGFloat {
    let widths = names.filter { !$0.isEmpty }.map {
      width(CardStrings.partOfSpeech($0), font: partOfSpeechFont)
    }
    return (widths.max() ?? 0).rounded(.up)
  }

  /// The width of every part-of-speech chip on a card with `names`, 0 for none.
  static func chipWidth(_ names: [String]) -> CGFloat {
    let label = partOfSpeechWidth(names)
    return label == 0 ? 0 : max(minimumChipWidth, label + chipPadding * 2)
  }

  /// The width of the collocations' phrase column: the widest phrase, up to the cap.
  static func phraseWidth(_ phrases: [String]) -> CGFloat {
    let widths = phrases.map { width($0, font: Typography.phrase.nsFont) }
    return min((widths.max() ?? 0).rounded(.up), maximumPhraseWidth)
  }

  /// The first place `term` stands in `sentence` as whole words, in any case.
  static func termRange(_ term: String, in sentence: String) -> Range<String.Index>? {
    guard !term.isEmpty else { return nil }
    var start = sentence.startIndex
    while let range = sentence.range(
      of: term, options: .caseInsensitive, range: start..<sentence.endIndex)
    {
      let before =
        range.lowerBound == sentence.startIndex
        ? nil : sentence[sentence.index(before: range.lowerBound)]
      let after = range.upperBound == sentence.endIndex ? nil : sentence[range.upperBound]
      if before?.isLetter != true && after?.isLetter != true { return range }
      start = sentence.index(after: range.lowerBound)
    }
    return nil
  }

  /// `sentence` with `term` on the highlight colour.
  static func marking(_ term: String, in sentence: String) -> AttributedString {
    var marked = AttributedString(sentence)
    if let range = termRange(term, in: sentence),
      let lower = AttributedString.Index(range.lowerBound, within: marked),
      let upper = AttributedString.Index(range.upperBound, within: marked)
    {
      marked[lower..<upper].backgroundColor = Color(Palette.highlight)
    }
    return marked
  }

  private static func width(_ text: String, font: NSFont) -> CGFloat {
    NSAttributedString(string: text, attributes: [.font: font]).size().width
  }
}

extension FrequencyBand {
  /// Only common words get the green pill; the others are a fact, not praise.
  var tone: Tone { self == .common ? .success : .neutral }
}

/// The card's own measures, from the mockup (Design/option-a/card.html).
extension Typography {
  /// A word too long for `headword` on one line.
  static let compactHeadword = TextStyle(size: 22, weight: .bold, tracking: -0.4)
  static let partOfSpeech = TextStyle(size: 12, weight: .semibold)
  /// The US or UK tag before the pronunciation.
  static let tag = TextStyle(size: 10.5, weight: .semibold)
  /// A collocation.
  static let phrase = TextStyle(size: 14, weight: .semibold)
}

extension Spacing {
  /// Between the main senses, the word and its pronunciation, a heading and its rows.
  static let senses: CGFloat = 8
  /// Between the rows of the other meanings and the examples.
  static let minorRows: CGFloat = 6
  /// Between a sentence and its translation.
  static let pair: CGFloat = 2
}

extension Size {
  static let partOfSpeechHeight: CGFloat = 18
}

extension Radius {
  static let tag: CGFloat = 4
}

/// A part of speech on its chip, then the sense. The chip keeps its place for a sense with no
/// part of speech, so the senses still line up.
private struct SenseRow: View {
  let partOfSpeech: String
  let text: String
  let chip: CGFloat
  let style: TextStyle

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: chip > 0 ? Spacing.pill : 0) {
      if chip > 0 {
        Text(partOfSpeech.isEmpty ? "" : CardStrings.partOfSpeech(partOfSpeech))
          .font(Typography.partOfSpeech.font)
          .foregroundStyle(Tone.accent.onTint)
          .lineLimit(1)
          .frame(width: chip, height: Size.partOfSpeechHeight)
          .background(
            partOfSpeech.isEmpty ? .clear : Tone.accent.tint,
            in: RoundedRectangle(cornerRadius: Radius.partOfSpeech, style: .continuous))
      }
      Wrapped(text, style: style)
    }
  }
}

/// A small heading over its rows: 其他义项, 例句, 搭配.
private struct CardSection<Content: View>: View {
  let title: String
  let spacing: CGFloat
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.senses) {
      Text(title)
        .font(Typography.label.font)
        .foregroundStyle(Color(Palette.textSecondary))
      VStack(alignment: .leading, spacing: spacing) { content }
    }
  }
}

/// Text that wraps to the panel's width instead of growing it.
private struct Wrapped: View {

  let text: String
  let style: TextStyle
  var color = Palette.textPrimary

  init(_ text: String, style: TextStyle, color: NSColor = Palette.textPrimary) {
    self.text = text
    self.style = style
    self.color = color
  }

  var body: some View {
    Text(text)
      .font(style.font)
      .lineSpacing(style.lineSpacing)
      .foregroundStyle(Color(color))
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }
}
