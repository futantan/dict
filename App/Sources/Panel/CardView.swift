// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import SwiftUI

/// The word card in the panel (architecture 6.6): the dictionary layer on top, then the
/// meaning in this sentence and the model's other fields as they arrive.
struct CardView: View {
  let card: CardState

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      if !card.senses.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(Array(card.senses.enumerated()), id: \.offset) { _, sense in
            SenseRow(partOfSpeech: sense.partOfSpeech, text: sense.gloss)
          }
        }
      }
      if card.model == .loading || card.definition != nil {
        Divider()
        inThisSentence
      }
      if !card.otherSenses.isEmpty {
        Section(title: CardStrings.otherSenses) {
          ForEach(Array(card.otherSenses.enumerated()), id: \.offset) { _, sense in
            SenseRow(partOfSpeech: sense.partOfSpeech, text: sense.definition)
          }
        }
      }
      if !card.examples.isEmpty {
        Section(title: CardStrings.examples) {
          ForEach(Array(card.examples.enumerated()), id: \.offset) { _, example in
            VStack(alignment: .leading, spacing: 2) {
              Wrapped(example.sentence, size: 13)
              Wrapped(example.translation, size: 12.5, secondary: true)
            }
          }
        }
      }
      if !card.collocations.isEmpty {
        Section(title: CardStrings.collocations) {
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

  @ViewBuilder private var inThisSentence: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Heading(CardStrings.inThisSentence)
        if card.model == .loading {
          ProgressView()
            .controlSize(.mini)
            .accessibilityLabel(CardStrings.lookingUp)
        }
      }
      if let definition = card.definition {
        Wrapped(definition, size: 15, weight: .medium)
      } else {
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

private struct SenseRow: View {
  let partOfSpeech: String
  let text: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(CardStrings.partOfSpeech(partOfSpeech))
        .font(.system(size: 12).italic())
        .foregroundStyle(.secondary)
        .frame(minWidth: 30, alignment: .leading)
      Wrapped(text, size: 14)
    }
  }
}

private struct Section<Content: View>: View {
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
    Text(title)
      .font(.system(size: 11, weight: .semibold))
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
