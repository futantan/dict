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
  /// Reports the height the content wants, the bar included; the controller sizes the window
  /// from it.
  var onContentHeight: (CGFloat) -> Void = { _ in }

  @State private var isScrolledToEnd = false

  var body: some View {
    let barHeight = ActionBar.shows(model.state) ? PanelLayout.barHeight : 0
    // While more text lies below, the panel takes an opaque fill for the text to fade into:
    // its own fill lets a trace of the material through, which no fade colour would match.
    let fade = model.isScrollable && !isScrolledToEnd ? Color(Palette.panelFill) : nil
    // The bar stays at the bottom while the content above it scrolls.
    VStack(spacing: 0) {
      ScrollView(.vertical) {
        PanelContent(
          model: model, onSubmit: onSubmit, onAction: onAction, onToggleChange: onToggleChange
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        // One report with the bar's fixed height, so the window never sees a stale half.
        .onGeometryChange(
          for: CGFloat.self, of: { $0.size.height + barHeight }, action: onContentHeight)
      }
      .scrollDisabled(!model.isScrollable)
      .scrollIndicators(model.isScrollable ? .automatic : .never)
      .onScrollGeometryChange(
        for: Bool.self, of: { $0.visibleRect.maxY >= $0.contentSize.height - 1 }
      ) { isScrolledToEnd = $1 }
      // Text that scrolls on fades out, then leaves the content's bottom margin clear, until
      // the end shows. Within the content's width, so a scroller stays clear too.
      .overlay(alignment: .bottom) {
        if let fade {
          VStack(spacing: 0) {
            LinearGradient(colors: [fade.opacity(0), fade], startPoint: .top, endPoint: .bottom)
              .frame(height: Size.scrollFade)
            fade.frame(height: model.state.bottomPadding)
          }
          .padding(.horizontal, Spacing.panel)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }
      }
      if ActionBar.shows(model.state) {
        ActionBar(state: model.state, onAction: onAction, onConfirm: onConfirm)
          .padding(.horizontal, Spacing.panel)
          .padding(.bottom, Spacing.panelBottom)
          .frame(height: barHeight, alignment: .top)
      }
    }
    .frame(width: PanelLayout.width)
    .background(fade)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(
      String(localized: "Dict panel", table: "Panel", comment: "Accessibility label of the panel")
    )
    .appleTranslationHost()
  }
}

/// The original, what the phase shows and the note, in that order: what scrolls above the
/// bottom bar.
private struct PanelContent: View {
  let model: PanelModel
  let onSubmit: (String) -> Void
  let onAction: (PanelAction.ID) -> Void
  let onToggleChange: (Int) -> Void

  var body: some View {
    let state = model.state
    if state.phase == .input {
      InputField(model: model, onSubmit: onSubmit)
    } else {
      VStack(alignment: .leading, spacing: Spacing.section) {
        if let source = state.source {
          SourceText(text: source)
          Hairline()
        }
        PanelBody(model: model, onAction: onAction, onToggleChange: onToggleChange)
        if let note = state.note, state.phase.showsNote {
          NoteLine(note: note, isWarning: state.phase.isPartial, onAction: onAction)
        }
      }
      .padding([.top, .leading], Spacing.panel)
      .padding(.trailing, PanelLayout.trailingPadding(isScrollable: model.isScrollable))
      .padding(.bottom, state.bottomPadding)
    }
  }
}

/// What the phase shows between the original and the bar.
private struct PanelBody: View {
  let model: PanelModel
  let onAction: (PanelAction.ID) -> Void
  let onToggleChange: (Int) -> Void

  var body: some View {
    switch model.state.phase {
    case .input:
      EmptyView()
    case .reading:
      ProgressLine(text: PanelStrings.reading)
    case .generating(let text) where text.isEmpty:
      ProgressLine(text: PanelStrings.translating, height: Typography.result.lineHeight)
    case .generating(let text):
      ResultText(text: text, isStreaming: true)
    case .result(let text), .partial(let text):
      ResultText(text: text, isStreaming: false)
    case .failure(let notice):
      NoticeView(
        notice: notice, defaultSymbol: "exclamationmark.triangle",
        tone: notice.kind == .information ? .neutral : .warning,
        onAction: onAction)
    case .needsSetup(let notice):
      NoticeView(notice: notice, defaultSymbol: "gearshape", tone: .accent, onAction: onAction)
    case .checking(let text):
      CheckingView(text: text)
    case .corrected(let correction):
      CorrectedView(correction: correction, onToggleChange: onToggleChange)
    case .card(let card):
      CardView(card: card, onAction: onAction)
    case .translatedOut(let translation):
      TranslatedOutView(translation: translation)
    }
  }
}

/// The panel's own wording (table `Panel`).
enum PanelStrings {
  static let reading = String(
    localized: "Reading the selection…", table: "Panel",
    comment: "Shown while the selected text is being read")
  static let translating = String(
    localized: "Translating…", table: "Panel",
    comment: "Shown until the first words of the result arrive")
  static let incomplete = String(
    localized: "Incomplete", table: "Panel",
    comment: "Status pill under a translation that stopped before it was complete")
  static let copy = String(
    localized: "Copy", table: "Panel", comment: "Button under a translation that copies it")
}

/// The captured or typed text above the result, in at most four lines.
struct SourceText: View {
  let text: String

  var body: some View {
    // Blank lines between paragraphs would waste the few lines the source gets.
    SelectableText(
      text: text.replacing(/\n\s*\n/, with: "\n"), font: Typography.callout.nsFont,
      color: Palette.textSecondary, lineSpacing: Typography.callout.lineSpacing,
      maximumLines: 4,
      accessibilityLabel: String(
        localized: "Original text", table: "Panel", comment: "Accessibility label"))
  }
}

/// A translation, with a spinner after its last word while it streams.
struct ResultText: View {
  let text: String
  let isStreaming: Bool

  var body: some View {
    let style = Typography.result
    SelectableText(
      text: text, font: style.nsFont, color: Palette.textPrimary, lineSpacing: style.lineSpacing
    )
    // Over the text, so the spinner never adds to the panel's height.
    .overlay(alignment: .topLeading) {
      if isStreaming {
        GeometryReader { proxy in
          Spinner()
            .accessibilityLabel(PanelStrings.translating)
            .offset(
              Self.spinnerOrigin(after: text, style: style, width: proxy.size.width)
                .offsetSize)
        }
      }
    }
  }

  /// Where the spinner's top left goes for `text` laid out as `SelectableText` lays it out
  /// at `width`: after the last word, centred on its line; at the trailing edge when the
  /// line is full.
  static func spinnerOrigin(after text: String, style: TextStyle, width: CGFloat) -> CGPoint {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = style.lineSpacing
    let storage = NSTextStorage(
      string: text, attributes: [.font: style.nsFont, .paragraphStyle: paragraph])
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    layout.addTextContainer(container)
    storage.addLayoutManager(layout)
    layout.ensureLayout(for: container)

    let line =
      layout.numberOfGlyphs > 0
      ? layout.lineFragmentUsedRect(forGlyphAt: layout.numberOfGlyphs - 1, effectiveRange: nil)
      : .zero
    let x = min(line.maxX + Spacing.tight, width - Size.spinner)
    return CGPoint(x: max(x, 0), y: line.minY + (style.lineHeight - Size.spinner) / 2)
  }
}

extension CGPoint {
  fileprivate var offsetSize: CGSize { CGSize(width: x, height: y) }
}

/// A remark under a result in a rounded block, with an optional button at its end: grey,
/// or in the warning colours when it says why a result is incomplete.
struct NoteLine: View {
  let note: PanelNote
  var isWarning = false
  let onAction: (PanelAction.ID) -> Void

  var body: some View {
    let tone = isWarning ? Tone.warning : .neutral
    HStack(alignment: .center, spacing: Spacing.buttons) {
      // The icon stays on the first line of a note that wraps; the button is centred.
      HStack(alignment: .firstTextBaseline, spacing: Spacing.buttons) {
        Image(systemName: isWarning ? "exclamationmark.triangle" : "info.circle")
          .accessibilityHidden(true)
        Text(note.text)
          .lineSpacing(Typography.note.lineSpacing)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let action = note.action {
        SecondaryButton(title: action.title, isCompact: true) { onAction(action.id) }
      }
    }
    .font(Typography.note.font)
    .foregroundStyle(tone.onTint)
    .padding(.vertical, Spacing.buttons)
    .padding(.leading, Spacing.pill)
    // A button keeps as close to the end as to the top and bottom.
    .padding(.trailing, note.action == nil ? Spacing.pill : Spacing.buttons)
    .background(tone.tint, in: RoundedRectangle(cornerRadius: Radius.block, style: .continuous))
  }
}

/// A spinner and what is being waited for, at least `height` tall: the height of the line
/// it stands in for, so the panel keeps its height when that line arrives.
struct ProgressLine: View {
  let text: String
  var height: CGFloat = 0

  var body: some View {
    HStack(spacing: Spacing.buttons) {
      Spinner()
      Text(text)
        .font(Typography.callout.font)
        .foregroundStyle(Color(Palette.textSecondary))
    }
    .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
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
    HStack(spacing: Spacing.row) {
      Image(systemName: "character.bubble")
        .font(.system(size: Size.symbol, weight: Size.symbolWeight))
        .foregroundStyle(Color(Palette.accent))
        .frame(width: Size.icon, height: Size.icon)
        .accessibilityHidden(true)
      // The field's own prompt keeps the system's placeholder colour, so the placeholder is
      // drawn behind an empty prompt instead; the label still names the field.
      TextField(text: $model.draft, prompt: Text(verbatim: "")) { Text(placeholder) }
        .background(alignment: .leading) {
          if model.draft.isEmpty {
            Text(placeholder)
              .foregroundStyle(Color(Palette.textSecondary))
              .accessibilityHidden(true)
          }
        }
        .textFieldStyle(.plain)
        .font(Typography.body.font)
        .focused($focused)
        .onSubmit {
          let text = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
          if !text.isEmpty { onSubmit(text) }
        }
    }
    .padding(.horizontal, Spacing.input)
    .frame(height: Size.inputHeight)
    .task(id: model.presentation) { focused = true }
  }
}

extension PanelLayout {
  /// The bottom bar with the space above its buttons and the panel's margin below them.
  static let barHeight = Spacing.barTop + Size.iconButton + Spacing.panelBottom

  /// The content's trailing margin. A legacy scroller, shown when scroll bars always show
  /// or a mouse is attached, takes its width from the scroll view's content; the margin
  /// gives it back, so the content keeps one width and one trailing edge either way.
  @MainActor static func trailingPadding(
    isScrollable: Bool, scrollerStyle: NSScroller.Style = NSScroller.preferredScrollerStyle
  ) -> CGFloat {
    guard isScrollable, scrollerStyle == .legacy else { return Spacing.panel }
    return Spacing.panel - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
  }
}

extension PanelState {
  /// Under the content: the space between the blocks above the bar; less above a notice's
  /// buttons, which are taller than a line of text.
  fileprivate var bottomPadding: CGFloat {
    if ActionBar.shows(self) { return Spacing.section }
    switch phase {
    case .failure(let notice), .needsSetup(let notice):
      return notice.actions.isEmpty ? Spacing.panel : Spacing.panelBottom
    default:
      return Spacing.panel
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

  fileprivate var isPartial: Bool {
    if case .partial = self { true } else { false }
  }
}
