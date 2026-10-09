// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import SwiftUI

/// The word card in the panel (architecture 6.6): the main senses on top, the dictionary's
/// or else the model's, then the meaning in this sentence and the model's other fields as
/// they arrive.
struct CardView: View {
  let card: CardState

  var body: some View {
    let main = card.mainSenses
    // One column for every part of speech on the card, as narrow as the widest label, so
    // the senses and the other meanings share one left edge.
    let column = CardLayout.partOfSpeechWidth(
      main.map(\.partOfSpeech) + card.otherSenses.map(\.partOfSpeech))
    let followed =
      card.showsSentenceSection || !card.otherSenses.isEmpty || !card.examples.isEmpty
      || !card.collocations.isEmpty
    VStack(alignment: .leading, spacing: 12) {
      header
      if !main.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(Array(main.enumerated()), id: \.offset) { _, sense in
            SenseRow(partOfSpeech: sense.partOfSpeech, text: sense.gloss, column: column)
          }
        }
      } else if card.model == .loading {
        LookingUp()
      }
      if followed && (!main.isEmpty || card.model == .loading) { Divider() }
      if card.showsSentenceSection {
        inThisSentence(spinning: card.model == .loading && !main.isEmpty)
      }
      if !card.otherSenses.isEmpty {
        CardSection(title: CardStrings.otherSenses) {
          ForEach(Array(card.otherSenses.enumerated()), id: \.offset) { _, sense in
            SenseRow(partOfSpeech: sense.partOfSpeech, text: sense.definition, column: column)
          }
        }
      }
      if !card.examples.isEmpty {
        CardSection(title: CardStrings.examples) {
          ForEach(Array(card.examples.enumerated()), id: \.offset) { _, example in
            VStack(alignment: .leading, spacing: 2) {
              Wrapped(example.sentence, size: 13)
              Wrapped(example.translation, size: 12.5, secondary: true)
            }
          }
        }
      }
      if !card.collocations.isEmpty {
        CardSection(title: CardStrings.collocations) {
          ForEach(Array(card.collocations.enumerated()), id: \.offset) { _, collocation in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(collocation.phrase).font(.system(size: 13, weight: .medium))
              Wrapped(collocation.meaning, size: 12.5, secondary: true)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(card.lemma)
        .font(.system(size: 20, weight: .semibold))
      if let phonetic = card.phonetic {
        Text(phonetic)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
      }
      if let band = card.band {
        Text(CardStrings.band(band))
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
      }
      Spacer(minLength: 0)
      if let count = card.shownEncounters {
        Text(CardStrings.encounters(count))
          .font(.system(size: 11.5))
          .foregroundStyle(.secondary)
          .fixedSize()
      }
    }
  }

  private func inThisSentence(spinning: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Heading(CardStrings.inThisSentence)
        if spinning {
          ProgressView()
            .controlSize(.mini)
            .accessibilityLabel(CardStrings.lookingUp)
        }
      }
      if let meaning = card.sentenceMeaning {
        Wrapped(meaning, size: 15, weight: .medium)
      } else if !card.senses.isEmpty {
        Text(CardStrings.lookingUp)
          .font(.system(size: 13))
          .foregroundStyle(.tertiary)
      }
      if let context = card.context {
        Wrapped(context, size: 12.5, secondary: true)
      }
      if let translation = card.contextTranslation {
        Wrapped(translation, size: 13)
      }
    }
  }
}

/// The measures of the card that depend on its text.
enum CardLayout {
  static var partOfSpeechFont: NSFont {
    let regular = NSFont.systemFont(ofSize: 12)
    return NSFont(descriptor: regular.fontDescriptor.withSymbolicTraits(.italic), size: 12)
      ?? regular
  }
  /// Between the part of speech and the sense.
  static let columnSpacing: CGFloat = 8

  /// The width of the part-of-speech column: the widest label among `names`, 0 for none.
  static func partOfSpeechWidth(_ names: [String]) -> CGFloat {
    let widths = names.filter { !$0.isEmpty }.map { name in
      NSAttributedString(
        string: CardStrings.partOfSpeech(name), attributes: [.font: partOfSpeechFont]
      ).size().width
    }
    return (widths.max() ?? 0).rounded(.up)
  }
}

private struct SenseRow: View {
  let partOfSpeech: String
  let text: String
  let column: CGFloat

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: column > 0 ? CardLayout.columnSpacing : 0) {
      if column > 0 {
        Text(partOfSpeech.isEmpty ? "" : CardStrings.partOfSpeech(partOfSpeech))
          .font(Font(CardLayout.partOfSpeechFont))
          .foregroundStyle(.secondary)
          .frame(minWidth: column, alignment: .leading)
          .fixedSize()
      }
      Wrapped(text, size: 14)
    }
  }
}

/// In place of the main senses until the model's definition arrives.
private struct LookingUp: View {
  var body: some View {
    HStack(spacing: 6) {
      ProgressView().controlSize(.mini)
      Text(CardStrings.lookingUp)
        .font(.system(size: 13))
        .foregroundStyle(.tertiary)
    }
  }
}

private struct CardSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Heading(title)
      content
    }
  }
}

private struct Heading: View {
  let title: String

  init(_ title: String) { self.title = title }

  var body: some View {
    // Small capitals carry a Latin heading at 11 pt; Chinese has no case, so it needs the
    // size to stand apart from the body text.
    let isLatin = title.unicodeScalars.allSatisfy(\.isASCII)
    Text(title)
      .font(.system(size: isLatin ? 11 : 12.5, weight: .semibold))
      .foregroundStyle(.secondary)
      .textCase(.uppercase)
  }
}

/// Text that wraps to the panel's width instead of growing it.
private struct Wrapped: View {
  let text: String
  var size: CGFloat
  var weight: Font.Weight = .regular
  var secondary = false

  init(_ text: String, size: CGFloat, weight: Font.Weight = .regular, secondary: Bool = false) {
    self.text = text
    self.size = size
    self.weight = weight
    self.secondary = secondary
  }

  var body: some View {
    Text(text)
      .font(.system(size: size, weight: weight))
      .foregroundStyle(secondary ? .secondary : .primary)
      .lineSpacing(2)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }
}
