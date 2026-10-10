// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import SwiftUI

/// The panel's observable state, owned by `PanelController`.
@MainActor
@Observable
final class PanelModel {
  var state: PanelState
  /// The text field's contents in the input phase.
  var draft = ""
  /// The content is taller than the panel; set by the controller after sizing the window.
  /// Only then does the scroll view show a scroller, which takes width from the content
  /// when scroll bars are set to always show.
  var isScrollable = false
  /// Counts `PanelController.show` calls, so the input field takes focus on every showing,
  /// not only the first: hiding the panel keeps its views alive.
  var presentation = 0

  init(state: PanelState = .input) {
    self.state = state
  }
}

/// The SwiftUI content of the result panel. The window chrome (material, corners, shadow)
/// belongs to `ResultPanel`.
struct PanelView: View {
  let model: PanelModel
  var onSubmit: (String) -> Void = { _ in }
  var onAction: (PanelAction.ID) -> Void = { _ in }
  var onConfirm: () -> Void = {}
  /// Reports the height the content wants; the controller sizes the window from it.
  var onContentHeight: (CGFloat) -> Void = { _ in }

  var body: some View {
    ScrollView(.vertical) {
      PanelContent(model: model, onSubmit: onSubmit, onAction: onAction, onConfirm: onConfirm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: onContentHeight)
    }
    .scrollDisabled(!model.isScrollable)
    .scrollIndicators(model.isScrollable ? .automatic : .never)
    .frame(width: PanelLayout.width)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(
      String(localized: "Dict panel", table: "Panel", comment: "Accessibility label of the panel")
    )
    .appleTranslationHost()
  }
}

private enum Metrics {
  static let padding: CGFloat = 16
  static let sectionSpacing: CGFloat = 12
  static let bodyFont = Font.system(size: 14)
  static let sourceFont = Font.system(size: 12.5)
  static var bodyNSFont: NSFont { .systemFont(ofSize: 14) }
  static var sourceNSFont: NSFont { .systemFont(ofSize: 12.5) }
  static let bodyLineSpacing: CGFloat = 3
}

private struct PanelContent: View {
  let model: PanelModel
  let onSubmit: (String) -> Void
  let onAction: (PanelAction.ID) -> Void
  let onConfirm: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      PanelBody(model: model, onSubmit: onSubmit, onAction: onAction)
      switch model.state.phase {
      case .checking:
        Divider()
        ActionBar(status: .checking)
      case .corrected(let correction):
        Divider()
        ActionBar(
          status: .corrected(correction),
          onReplace: onConfirm,
          onCopy: { copyToClipboard(correction.text) })
      case .card(let card):
        Divider()
        ActionBar(status: .card(card), onAction: onAction)
      case .result, .partial:
        if model.state.offersLookUp {
          Divider()
          ActionBar(status: .translation, onAction: onAction)
        }
      default:
        EmptyView()
      }
    }
  }
}

private struct PanelBody: View {
  let model: PanelModel
  let onSubmit: (String) -> Void
  let onAction: (PanelAction.ID) -> Void

  var body: some View {
    let state = model.state
    VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
      if let source = state.source, state.phase != .input {
        SourceText(text: source)
        Divider()
      }
      switch state.phase {
      case .input:
        InputField(model: model, onSubmit: onSubmit)
      case .reading:
        ProgressLine(
          text: String(
            localized: "Reading the selection…", table: "Panel",
            comment: "Shown while the selected text is being read"))
      case .generating(let text) where text.isEmpty:
        ProgressLine(
          text: String(
            localized: "Translating…", table: "Panel",
            comment: "Shown until the first words of the result arrive"))
      case .generating(let text):
        ResultText(text: text, isStreaming: true)
      case .result(let text), .partial(let text):
        ResultText(text: text, isStreaming: false)
      case .failure(let notice):
        NoticeView(
          notice: notice, defaultSymbol: "exclamationmark.triangle.fill", tint: .orange,
          onAction: onAction)
      case .needsSetup(let notice):
        NoticeView(
          notice: notice, defaultSymbol: "gearshape.fill", tint: .accentColor, onAction: onAction)
      case .checking(let text):
        SelectableText(
          text: text, font: Metrics.bodyNSFont, color: .secondaryLabelColor,
          lineSpacing: Metrics.bodyLineSpacing)
      case .corrected(let correction):
        SelectableText(
          text: correction.text,
          attributed: diffText(correction.segments),
          font: Metrics.bodyNSFont, lineSpacing: Metrics.bodyLineSpacing,
          accessibilityLabel: WritingStrings.title)
      case .card(let card):
        CardView(card: card)
      }
      if let note = state.note, state.phase.showsNote {
        NoteLine(note: note, onAction: onAction)
      }
    }
    .padding(state.phase == .input ? 0 : Metrics.padding)
  }
}

private struct SourceText: View {
  let text: String

  var body: some View {
    // Blank lines between paragraphs would waste the few lines the source gets.
    SelectableText(
      text: text.replacing(/\n\s*\n/, with: "\n"), font: Metrics.sourceNSFont,
      color: .secondaryLabelColor, lineSpacing: 2, maximumLines: 4,
      accessibilityLabel: String(
        localized: "Original text", table: "Panel", comment: "Accessibility label"))
  }
}

private struct ResultText: View {
  let text: String
  let isStreaming: Bool

  var body: some View {
    SelectableText(text: text, font: Metrics.bodyNSFont, lineSpacing: Metrics.bodyLineSpacing)
      .overlay(alignment: .bottomTrailing) {
        if isStreaming {
          ProgressView()
            .controlSize(.mini)
            .offset(x: 4, y: 4)
            .accessibilityLabel(
              String(
                localized: "Translating…", table: "Panel",
                comment: "Shown until the first words of the result arrive"))
        }
      }
  }
}

private struct NoteLine: View {
  let note: PanelNote
  let onAction: (PanelAction.ID) -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      Label(note.text, systemImage: "info.circle")
        .font(Metrics.sourceFont)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      if let action = note.action {
        Button(action.title) { onAction(action.id) }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .fixedSize()
      }
    }
  }
}

private struct ProgressLine: View {
  let text: String

  var body: some View {
    HStack(spacing: 8) {
      ProgressView().controlSize(.small)
      Text(text)
        .font(Metrics.bodyFont)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
  }
}

private struct InputField: View {
  @Bindable var model: PanelModel
  let onSubmit: (String) -> Void
  @FocusState private var focused: Bool

  private let placeholder = String(
    localized: "Type text to translate", table: "Panel",
    comment: "Placeholder of the panel's text field")

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "character.cursor.ibeam")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      TextField(placeholder, text: $model.draft)
        .textFieldStyle(.plain)
        .font(.system(size: 16))
        .focused($focused)
        .onSubmit {
          let text = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
          if !text.isEmpty { onSubmit(text) }
        }
    }
    .padding(.horizontal, Metrics.padding)
    .frame(height: 48)
    .task(id: model.presentation) { focused = true }
  }
}

private struct NoticeView: View {
  let notice: PanelNotice
  let defaultSymbol: String
  let tint: Color
  let onAction: (PanelAction.ID) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(systemName: notice.symbol ?? defaultSymbol)
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(tint)
          .frame(width: 18)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(notice.title)
            .font(.system(size: 13.5, weight: .semibold))
          if let message = notice.message {
            Text(message)
              .font(.system(size: 12.5))
              .foregroundStyle(.secondary)
              .lineSpacing(2)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      }
      if !notice.actions.isEmpty {
        HStack(spacing: 8) {
          Spacer(minLength: 0)
          ForEach(notice.actions) { action in
            ActionButton(action: action) { onAction(action.id) }
          }
        }
      }
    }
  }
}

private struct ActionButton: View {
  let action: PanelAction
  let perform: () -> Void

  var body: some View {
    if action.isDefault {
      Button(action.title, action: perform)
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    } else {
      Button(action.title, action: perform)
        .buttonStyle(.bordered)
    }
  }
}

extension PanelPhase {
  /// Only a result, streaming, finished or partial, carries a note.
  fileprivate var showsNote: Bool {
    switch self {
    case .generating, .result, .partial, .card: true
    case .input, .reading, .failure, .needsSetup, .checking, .corrected: false
    }
  }
}

// MARK: - Write flow

/// The proofread text with each change in place: the removed words struck through in red,
/// the inserted ones in green, a plain space between the two so they do not run together.
@MainActor
func diffText(_ segments: [DiffSegment]) -> NSAttributedString {
  let red = DiffColor.removed
  let green = DiffColor.inserted
  let paragraph = NSMutableParagraphStyle()
  paragraph.lineSpacing = Metrics.bodyLineSpacing
  let base: [NSAttributedString.Key: Any] = [
    .font: Metrics.bodyNSFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
  ]
  let text = NSMutableAttributedString()
  for segment in segments {
    switch segment {
    case .unchanged(let run):
      text.append(NSAttributedString(string: run, attributes: base))
    case .changed(let from, let to):
      if !from.isEmpty {
        var removed = base
        removed[.foregroundColor] = red
        removed[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        removed[.strikethroughColor] = red
        text.append(NSAttributedString(string: from, attributes: removed))
      }
      if !from.isEmpty && !to.isEmpty {
        text.append(NSAttributedString(string: " ", attributes: base))
      }
      if !to.isEmpty {
        var inserted = base
        inserted[.foregroundColor] = green
        inserted[.backgroundColor] = NSColor.systemGreen.withAlphaComponent(0.14)
        text.append(NSAttributedString(string: to, attributes: inserted))
      }
    }
  }
  return text
}

/// The diff's text colours. The system red and green are bright enough for dark mode, but
/// on the light fill green text reads at about 2:1, so in light mode both are darkened to
/// read at 4.5:1 or more on the fill, the strike-through with them.
enum DiffColor {
  static let removed = legible(.systemRed, darkening: 0.2)
  static let inserted = legible(.systemGreen, darkening: 0.45)

  private static func legible(_ color: NSColor, darkening fraction: CGFloat) -> NSColor {
    NSColor(name: nil) { appearance in
      guard appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua else { return color }
      return color.blended(withFraction: fraction, of: .black) ?? color
    }
  }
}

private func copyToClipboard(_ text: String) {
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(text, forType: .string)
}

/// The bar along the bottom of the Write panel and the word card, in the manner of a
/// launcher's action bar: what happened on the left, the actions and their keys on the right.
private struct ActionBar: View {
  enum Status {
    case checking
    case corrected(Correction)
    case card(CardState)
    /// A translation of a word or phrase, which can be looked up instead.
    case translation
  }

  let status: Status
  var onReplace: () -> Void = {}
  var onCopy: () -> Void = {}
  var onAction: (PanelAction.ID) -> Void = { _ in }

  var body: some View {
    HStack(spacing: 10) {
      summary
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
      if case .corrected(let correction) = status {
        if correction.canReplace {
          KeyedAction(
            title: WritingStrings.replaceAction, keys: ["↩"], isPrimary: true, perform: onReplace)
          Divider().frame(height: 14)
        }
        KeyedAction(
          title: WritingStrings.copyAction, keys: ["⌘", "C"], isPrimary: false, perform: onCopy)
      }
      if case .card(let card) = status {
        KeyedAction(
          title: card.isLearning ? CardStrings.learning : CardStrings.learn,
          symbol: card.isLearning ? "star.fill" : "star", keys: ["⌘", "S"],
          isPrimary: card.isLearning
        ) { onAction(CardStrings.learnAction) }
        Divider().frame(height: 14)
        KeyedAction(
          title: CardStrings.pronounce, symbol: "speaker.wave.2", keys: ["⌘", "P"],
          isPrimary: false
        ) { onAction(CardStrings.pronounceAction) }
        Divider().frame(height: 14)
        KeyedAction(title: CardStrings.translateAsSentence, keys: [], isPrimary: false) {
          onAction(CardStrings.translateAction)
        }
      }
      if case .translation = status {
        KeyedAction(title: CardStrings.lookUp, symbol: "character.book.closed", keys: []) {
          onAction(CardStrings.lookUpAction)
        }
      }
    }
    // The content's edges, so the bar's first and last words line up with the text above.
    .padding(.horizontal, Metrics.padding)
    .frame(height: 38)
  }

  @ViewBuilder private var summary: some View {
    switch status {
    case .checking:
      HStack(spacing: 6) {
        ProgressView().controlSize(.mini)
        Text(WritingStrings.checking)
      }
    case .card, .translation:
      // Keeps the actions at the trailing edge, as in the Write panel.
      Color.clear.frame(height: 1)
    case .corrected(let correction):
      if correction.changeCount == 0 {
        Label(WritingStrings.noMistakes, systemImage: "checkmark.circle.fill")
          .labelStyle(TintedIconLabelStyle(tint: .green))
      } else if !correction.canReplace {
        Label(WritingStrings.cannotReplace, systemImage: "info.circle")
      } else {
        Label(
          "\(WritingStrings.title) · \(WritingStrings.changes(correction.changeCount))",
          systemImage: "text.badge.checkmark")
      }
    }
  }

  private struct KeyedAction: View {
    let title: String
    var symbol: String?
    let keys: [String]
    var isPrimary = false
    let perform: () -> Void

    var body: some View {
      Button(action: perform) {
        HStack(spacing: 6) {
          if let symbol {
            Image(systemName: symbol)
              .font(.system(size: 11))
              .foregroundStyle(isPrimary ? Color.yellow : Color.secondary)
          }
          Text(title)
            .font(.system(size: 12, weight: isPrimary ? .semibold : .regular))
            .foregroundStyle(isPrimary ? .primary : .secondary)
          if !keys.isEmpty {
            // One key cap for the whole shortcut, as menus print it.
            Text(keys.joined())
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(.secondary)
              .padding(.horizontal, 5)
              .frame(minWidth: 18, minHeight: 18)
              .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
          }
        }
        .fixedSize()
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(title)
    }
  }
}

private struct TintedIconLabelStyle: LabelStyle {
  let tint: Color

  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 6) {
      configuration.icon.foregroundStyle(tint)
      configuration.title
    }
  }
}
