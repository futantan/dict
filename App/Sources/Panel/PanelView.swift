// SPDX-License-Identifier: GPL-3.0-or-later

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
  /// Reports the height the content wants; the controller sizes the window from it.
  var onContentHeight: (CGFloat) -> Void = { _ in }

  var body: some View {
    ScrollView(.vertical) {
      PanelContent(model: model, onSubmit: onSubmit, onAction: onAction)
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
  static let bodyLineSpacing: CGFloat = 3
}

private struct PanelContent: View {
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
      case .result(let text):
        ResultText(text: text, isStreaming: false)
      case .failure(let notice):
        NoticeView(
          notice: notice, defaultSymbol: "exclamationmark.triangle.fill", tint: .orange,
          onAction: onAction)
      case .needsSetup(let notice):
        NoticeView(
          notice: notice, defaultSymbol: "gearshape.fill", tint: .accentColor, onAction: onAction)
      }
      if let note = state.note, state.phase.showsNote {
        NoteLine(text: note)
      }
    }
    .padding(state.phase == .input ? 0 : Metrics.padding)
  }
}

private struct SourceText: View {
  let text: String

  var body: some View {
    // Blank lines between paragraphs would waste the few lines the source gets.
    Text(text.replacing(/\n\s*\n/, with: "\n"))
      .font(Metrics.sourceFont)
      .foregroundStyle(.secondary)
      .lineSpacing(2)
      .lineLimit(4)
      .truncationMode(.tail)
      .frame(maxWidth: .infinity, alignment: .leading)
      .textSelection(.enabled)
      .accessibilityLabel(
        String(localized: "Original text", table: "Panel", comment: "Accessibility label")
      )
      .accessibilityValue(text)
  }
}

private struct ResultText: View {
  let text: String
  let isStreaming: Bool

  var body: some View {
    Text(text)
      .font(Metrics.bodyFont)
      .lineSpacing(Metrics.bodyLineSpacing)
      .frame(maxWidth: .infinity, alignment: .leading)
      .textSelection(.enabled)
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
  let text: String

  var body: some View {
    Label(text, systemImage: "info.circle")
      .font(Metrics.sourceFont)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
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
  /// Only a result, streaming or finished, carries a note.
  fileprivate var showsNote: Bool {
    switch self {
    case .generating, .result: true
    case .input, .reading, .failure, .needsSetup: false
    }
  }
}
