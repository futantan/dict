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
  /// Return, ⌘Return (true) or a click on Replace.
  var onConfirm: (_ anyway: Bool) -> Void = { _ in }
  /// A click on a change of the correction shown; the value is its index.
  var onToggleChange: (Int) -> Void = { _ in }
  /// Reports the height the content wants; the controller sizes the window from it.
  var onContentHeight: (CGFloat) -> Void = { _ in }

  var body: some View {
    ScrollView(.vertical) {
      PanelContent(
        model: model, onSubmit: onSubmit, onAction: onAction, onConfirm: onConfirm,
        onToggleChange: onToggleChange
      )
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
  /// One line of the result, so a progress line in its place is exactly as tall and the
  /// panel keeps its height when the first words arrive.
  static var bodyLineHeight: CGFloat {
    NSLayoutManager().defaultLineHeight(for: bodyNSFont).rounded(.up)
  }
}

private struct PanelContent: View {
  let model: PanelModel
  let onSubmit: (String) -> Void
  let onAction: (PanelAction.ID) -> Void
  let onConfirm: (_ anyway: Bool) -> Void
  let onToggleChange: (Int) -> Void

  var body: some View {
    VStack(spacing: 0) {
      PanelBody(
        model: model, onSubmit: onSubmit, onAction: onAction, onToggleChange: onToggleChange)
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
      case .translatedOut(let translation):
        Divider()
        ActionBar(
          status: .translatedOut(translation),
          onReplace: onConfirm,
          onCopy: { copyToClipboard(translation.text) })
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
  let onToggleChange: (Int) -> Void

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
          attributed: diffText(
            correction.proposed.segments, accepted: correction.accepted,
            current: correction.current),
          font: Metrics.bodyNSFont, lineSpacing: Metrics.bodyLineSpacing,
          accessibilityLabel: WritingStrings.title, onClickChange: onToggleChange
        )
        .help(correction.changeCount > 0 ? WritingStrings.reviewHelp : "")
      case .card(let card):
        CardView(card: card)
      case .translatedOut(let translation):
        TranslatedOutView(translation: translation)
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
    .frame(maxWidth: .infinity, minHeight: Metrics.bodyLineHeight, alignment: .leading)
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
    case .generating, .result, .partial, .card, .translatedOut: true
    case .input, .reading, .failure, .needsSetup, .checking, .corrected: false
    }
  }
}

// MARK: - Write flow

/// A translate-out: the translation as the main text, then one line with the
/// back-translation, then what to check before replacing (architecture 11.6). The
/// back-translation line is there from the start, so the panel does not grow when it arrives.
private struct TranslatedOutView: View {
  let translation: TranslateOut

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
      if translation.text.isEmpty && !translation.isComplete {
        ProgressLine(
          text: String(
            localized: "Translating…", table: "Panel",
            comment: "Shown until the first words of the result arrive"))
      } else {
        ResultText(text: translation.text, isStreaming: !translation.isComplete)
      }
      BackTranslationLine(translation: translation)
      if translation.isComplete && !translation.shownIssues.isEmpty {
        IssueList(issues: translation.shownIssues)
      }
    }
  }
}

/// The badge, then the back-translation or what stands in for it.
private struct BackTranslationLine: View {
  let translation: TranslateOut

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(WritingStrings.backTranslation)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        .fixedSize()
      content
        .font(Metrics.sourceFont)
        .lineSpacing(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private var content: some View {
    switch translation.backTranslation {
    case .text(let text):
      Text(text)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    case .pending where translation.isComplete:
      Text(WritingStrings.backTranslating).foregroundStyle(.tertiary)
    case .pending:
      Text(WritingStrings.backTranslationWaiting).foregroundStyle(.tertiary)
    case .unavailable:
      Text(WritingStrings.backTranslationUnavailable).foregroundStyle(.tertiary)
    }
  }
}

/// The validation's issues, in the warning colour of the panel's notices.
private struct IssueList: View {
  let issues: [RewriteIssue]

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        ForEach(issues, id: \.self) { issue in
          Text(WritingStrings.issue(issue))
        }
      }
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
    }
    .font(Metrics.sourceFont)
  }
}

/// The proofread text with each change in place. An accepted change shows the removed
/// words struck through in red and the inserted ones in green; a declined one shows the
/// original words, then the declined suggestion struck through and faint (a declined
/// deletion, which has none, underlines the kept words thinly). A plain space keeps the two sides from running together. The current change, the
/// one ← → and Space act on, is underlined in the accent colour. Every character of a change
/// carries its index (`.dictChange`) for clicks, and the pointing hand.
///
/// - Parameter accepted: The accepted changes; nil accepts every one.
@MainActor
func diffText(
  _ segments: [DiffSegment], accepted: Set<Int>? = nil, current: Int? = nil
) -> NSAttributedString {
  let red = DiffColor.removed
  let green = DiffColor.inserted
  let paragraph = NSMutableParagraphStyle()
  paragraph.lineSpacing = Metrics.bodyLineSpacing
  let base: [NSAttributedString.Key: Any] = [
    .font: Metrics.bodyNSFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
  ]
  let text = NSMutableAttributedString()
  var change = 0
  for segment in segments {
    guard case .changed(let from, let to) = segment else {
      if case .unchanged(let run) = segment {
        text.append(NSAttributedString(string: run, attributes: base))
      }
      continue
    }
    let isAccepted = accepted?.contains(change) ?? true
    let isCurrent = change == current
    var marked = base
    marked[.dictChange] = change
    marked[.cursor] = NSCursor.pointingHand
    if isCurrent {
      marked[.underlineStyle] = NSUnderlineStyle.thick.rawValue
      marked[.underlineColor] = NSColor.controlAccentColor
    }
    if !from.isEmpty {
      var removed = marked
      if isAccepted {
        removed[.foregroundColor] = red
        removed[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        removed[.strikethroughColor] = red
      } else if to.isEmpty && !isCurrent {
        // A declined deletion has no faint suggestion to mark it.
        removed[.underlineStyle] = NSUnderlineStyle.single.rawValue
        removed[.underlineColor] = NSColor.secondaryLabelColor
      }
      text.append(NSAttributedString(string: from, attributes: removed))
    }
    if !from.isEmpty && !to.isEmpty {
      // Underlined with the change when current, so the change reads as one piece.
      text.append(NSAttributedString(string: " ", attributes: marked))
    }
    if !to.isEmpty {
      var inserted = marked
      if isAccepted {
        inserted[.foregroundColor] = green
        inserted[.backgroundColor] = NSColor.systemGreen.withAlphaComponent(0.14)
      } else {
        inserted[.foregroundColor] = NSColor.tertiaryLabelColor
        inserted[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        inserted[.strikethroughColor] = NSColor.tertiaryLabelColor
      }
      text.append(NSAttributedString(string: to, attributes: inserted))
    }
    change += 1
  }
  return text
}

extension NSAttributedString.Key {
  /// The index of the change a character of the diff belongs to (`diffText`).
  static let dictChange = NSAttributedString.Key("DictChange")
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
    case translatedOut(TranslateOut)
  }

  let status: Status
  var onReplace: (_ anyway: Bool) -> Void = { _ in }
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
        // With every change declined Return only explains that nothing is replaced.
        if correction.canReplace && !correction.accepted.isEmpty {
          KeyedAction(
            title: WritingStrings.replaceAction, keys: ["↩"], isPrimary: true
          ) { onReplace(false) }
          Divider().frame(height: 14)
        }
        KeyedAction(
          title: WritingStrings.copyAction, keys: ["⌘", "C"], isPrimary: false, perform: onCopy)
      }
      if case .translatedOut(let translation) = status, translation.isComplete {
        if translation.replacesOnReturn {
          KeyedAction(
            title: WritingStrings.replaceAction, keys: ["↩"], isPrimary: true
          ) { onReplace(false) }
          Divider().frame(height: 14)
        } else if translation.canReplace {
          KeyedAction(
            title: WritingStrings.replaceAnywayAction, keys: ["⌘", "↩"], isPrimary: false
          ) { onReplace(true) }
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
    case .translatedOut(let translation):
      // While streaming, the spinner is the text's own, as when reading.
      if translation.isComplete && !translation.issues.isEmpty {
        Label(WritingStrings.checkBeforeReplacing, systemImage: "exclamationmark.circle.fill")
          .labelStyle(TintedIconLabelStyle(tint: .orange))
      } else if translation.isComplete && !translation.replaceable {
        Label(WritingStrings.cannotReplace, systemImage: "info.circle")
      } else {
        Label(WritingStrings.translateOutTitle, systemImage: "globe")
      }
    case .corrected(let correction):
      if correction.changeCount == 0 {
        Label(WritingStrings.noMistakes, systemImage: "checkmark.circle.fill")
          .labelStyle(TintedIconLabelStyle(tint: .green))
      } else if correction.declinedReturn {
        Label(WritingStrings.nothingReplaced, systemImage: "exclamationmark.circle.fill")
          .labelStyle(TintedIconLabelStyle(tint: .orange))
      } else if !correction.canReplace {
        Label(WritingStrings.cannotReplace, systemImage: "info.circle")
      } else if correction.accepted.isEmpty {
        Label(WritingStrings.allDeclined, systemImage: "arrow.uturn.backward.circle")
      } else {
        Label(
          """
          \(WritingStrings.title) · \
          \(WritingStrings.changes(correction.accepted.count, of: correction.changeCount))
          """,
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
