// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import SwiftUI

/// The settings page's 模型 section (Design/main-app/settings.html): the provider, the key,
/// the model and the Test button in one card like the page's others, with the custom
/// provider's options and other providers' base URL under a collapsed 高级. It shows
/// `SettingsModel` as the onboarding's `ModelSections` does and says what `ModelStatus` says;
/// the key is saved when its field loses focus or the section goes away.
struct ModelSettingsSection: View {
  let model: SettingsModel

  @State private var showsAdvanced: Bool
  @State private var isKeyVisible = false
  @FocusState private var isKeyFocused: Bool

  init(model: SettingsModel, showsAdvanced: Bool = false) {
    self.model = model
    _showsAdvanced = State(initialValue: showsAdvanced)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: WindowLayout.headingSpacing) {
      SectionHeading(SettingsSection.model.title)
      WindowCard {
        providerRow
        if let preset = model.selectedPreset {
          let isCustom = preset.id == ProviderPreset.customID
          if isCustom {
            CardDivider()
            fieldRow(ModelText.baseURL) { baseURLField(preset) }
          }
          if model.acceptsKey {
            CardDivider()
            keyRow(preset)
          }
          CardDivider()
          modelRow(preset)
          CardDivider()
          testRow
          if case .checked(let report) = model.connection {
            ForEach(
              ModelStatus.checks(
                report, isCustom: isCustom, hasListedModels: model.hasListedModels),
              id: \.title
            ) { check in
              CardDivider()
              SettingsRow(title: check.title, subtitle: subtitle(check.details)) {
                CheckIcon(state: check.state)
                  .font(.system(size: Size.symbol))
                  .frame(width: Size.icon, height: Size.icon)
              }
              .textSelection(.enabled)
            }
          }
          CardDivider()
          advancedRow(isCustom: isCustom)
          if showsAdvanced { advanced(preset) }
        }
      }
      note
    }
    .onChange(of: isKeyFocused) { _, focused in if !focused { model.commitKey() } }
    .onDisappear { model.commitKey() }
  }

  // MARK: Rows

  private var providerRow: some View {
    let picker = ProviderPicker(
      options: [nil] + model.presets.map(\.id),
      selection: model.preferences.model.providerID,
      select: { model.selectProvider($0) })
    // Side by side, or the segments under the label when the column is too narrow.
    return ViewThatFits(in: .horizontal) {
      HStack(spacing: Spacing.input) {
        rowTitle(ModelText.provider)
        Spacer(minLength: 0)
        picker
      }
      VStack(alignment: .leading, spacing: Spacing.buttons) {
        rowTitle(ModelText.provider)
        picker
      }
      .padding(.vertical, WindowLayout.cardRowVertical)
    }
    .padding(.horizontal, WindowLayout.cardRowHorizontal)
    .frame(minHeight: ModelCardLayout.rowMinHeight)
  }

  /// A title and a field on the right, as wide as the mockup's and narrower when it must.
  private func fieldRow<Field: View>(
    _ title: String, @ViewBuilder field: () -> Field
  ) -> some View {
    HStack(spacing: Spacing.input) {
      rowTitle(title)
      Spacer(minLength: 0)
      field()
        .frame(minWidth: ModelCardLayout.fieldMinWidth, maxWidth: ModelCardLayout.fieldMaxWidth)
    }
    .padding(.horizontal, WindowLayout.cardRowHorizontal)
    .frame(minHeight: ModelCardLayout.rowMinHeight)
  }

  private func baseURLField(_ preset: ProviderPreset) -> some View {
    TextField(text: model.binding(\.baseURL), prompt: prompt(ModelText.baseURLPrompt(preset))) {
      Text(ModelText.baseURL)
    }
    .cardField()
  }

  /// The key with 显示, then where it is kept, or what is wrong with the fields.
  private func keyRow(_ preset: ProviderPreset) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: Spacing.input) {
        rowTitle(ModelText.apiKey)
        Spacer(minLength: 0)
        HStack(spacing: Spacing.buttons) {
          keyField(preset)
            .frame(
              minWidth: ModelCardLayout.fieldMinWidth, maxWidth: ModelCardLayout.fieldMaxWidth)
          CardButton(title: isKeyVisible ? ModelCardText.hide : ModelCardText.show) {
            isKeyVisible.toggle()
          }
          .help(isKeyVisible ? ModelText.hideKeyHelp : ModelText.showKeyHelp)
        }
      }
      HStack(alignment: .firstTextBaseline, spacing: Spacing.input) {
        fieldsNote(preset)
        Spacer(minLength: 0)
        if model.keychainStatus == nil {
          Label(ModelCardText.inKeychain, systemImage: "lock")
            .labelStyle(NoteLabelStyle())
            .font(WindowType.footnote.font)
            .foregroundStyle(Color(Palette.textSecondary))
            .fixedSize()
        }
      }
    }
    .padding(.horizontal, WindowLayout.cardRowHorizontal)
    .padding(.vertical, WindowLayout.cardRowVertical)
  }

  @ViewBuilder
  private func keyField(_ preset: ProviderPreset) -> some View {
    Group {
      if isKeyVisible {
        TextField(text: model.keyBinding, prompt: prompt(ModelText.keyPrompt(preset))) {
          Text(ModelText.apiKey)
        }
      } else {
        SecureField(text: model.keyBinding, prompt: prompt(ModelText.keyPrompt(preset))) {
          Text(ModelText.apiKey)
        }
      }
    }
    .focused($isKeyFocused)
    .onSubmit { model.commitKey() }
    .cardField()
  }

  @ViewBuilder
  private func fieldsNote(_ preset: ProviderPreset) -> some View {
    switch ModelStatus.fieldsNote(model, preset: preset) {
    case .warning(let text):
      StatusNote(line: ModelStatusLine(text: text, kind: .warning))
    case .keyLink(let title, let url):
      Link(title, destination: url)
        .font(WindowType.footnote.font)
        .foregroundStyle(Color(Palette.accent))
    case nil:
      EmptyView()
    }
  }

  /// The name as typed, with the listed names in a menu, and 列出可用模型.
  private func modelRow(_ preset: ProviderPreset) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: Spacing.input) {
        rowTitle(ModelText.model)
        Spacer(minLength: 0)
        HStack(spacing: Spacing.buttons) {
          modelField(preset)
            .frame(
              minWidth: ModelCardLayout.fieldMinWidth, maxWidth: ModelCardLayout.modelMaxWidth)
          CardButton(title: ModelText.listModels) { model.listModels() }
            .disabled(!model.canListModels)
        }
      }
      if model.modelList != .idle {
        StatusNote(line: ModelStatus.modelList(model.modelList, preset: preset))
      }
      // Without a key row, what is wrong with the fields goes here.
      if !model.acceptsKey, case .warning(let text) = ModelStatus.fieldsNote(model, preset: preset)
      {
        StatusNote(line: ModelStatusLine(text: text, kind: .warning))
      }
    }
    .padding(.horizontal, WindowLayout.cardRowHorizontal)
    .padding(.vertical, ModelCardLayout.rowVertical)
    .frame(minHeight: ModelCardLayout.rowMinHeight)
  }

  private func modelField(_ preset: ProviderPreset) -> some View {
    HStack(spacing: Spacing.tight) {
      TextField(text: model.binding(\.model), prompt: prompt(ModelText.modelPrompt(preset))) {
        Text(ModelText.model)
      }
      .textFieldStyle(.plain)
      if model.hasListedModels {
        Menu {
          ListedModels(model: model)
        } label: {
          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: ModelCardLayout.chevron, weight: .semibold))
            .foregroundStyle(Color(Palette.textSecondary))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(ModelText.chooseListedModel)
      }
    }
    .cardField()
  }

  /// The result on a pill, or what the test does, and 测试 as the page's primary button.
  private var testRow: some View {
    HStack(spacing: Spacing.pill) {
      Group {
        if let summary = ModelStatus.summary(model.connection) {
          ResultPill(line: summary)
        } else {
          StatusNote(line: ModelStatus.connection(model.connection))
            .textSelection(.enabled)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      PrimaryButton(title: ModelText.test) { model.testConnection() }
        .disabled(!model.canTest)
        .opacity(model.canTest ? 1 : Size.disabledOpacity * 2)
    }
    .padding(.horizontal, WindowLayout.cardRowHorizontal)
    .padding(.vertical, ModelCardLayout.rowVertical)
    .frame(minHeight: ModelCardLayout.rowMinHeight)
  }

  private func advancedRow(isCustom: Bool) -> some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) { showsAdvanced.toggle() }
    } label: {
      HStack(spacing: Spacing.row) {
        Image(systemName: "chevron.right")
          .font(.system(size: ModelCardLayout.chevron, weight: .semibold))
          .foregroundStyle(Color(Palette.textSecondary))
          .rotationEffect(.degrees(showsAdvanced ? 90 : 0))
          .accessibilityHidden(true)
        rowTitle(ModelText.advanced)
        Text(isCustom ? ModelCardText.customOptions : ModelText.baseURL)
          .font(WindowType.footnote.font)
          .foregroundStyle(Color(Palette.textSecondary))
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .padding(.horizontal, WindowLayout.cardRowHorizontal)
      .frame(minHeight: WindowLayout.rowMinHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusRing(Rectangle())
    .accessibilityValue(showsAdvanced ? ModelCardText.expanded : ModelCardText.collapsed)
  }

  /// The custom provider's request options, or another provider's base URL.
  @ViewBuilder
  private func advanced(_ preset: ProviderPreset) -> some View {
    if preset.id == ProviderPreset.customID {
      let options = CustomOptions(model: model, preset: preset)
      CardDivider()
      SettingsRow(title: ModelText.jsonMode) { options.jsonMode.cardMenu() }
      CardDivider()
      SettingsRow(title: ModelText.thinking) { options.thinking.cardMenu() }
      CardDivider()
      SettingsRow(title: ModelText.outputLimit) { options.outputLimit.cardMenu() }
      Text(ModelText.advancedNote)
        .font(WindowType.footnote.font)
        .lineSpacing(WindowType.footnote.lineSpacing)
        .foregroundStyle(Color(Palette.textSecondary))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, WindowLayout.cardRowHorizontal)
        .padding(.bottom, WindowLayout.cardRowVertical)
    } else {
      CardDivider()
      fieldRow(ModelText.baseURL) { baseURLField(preset) }
    }
  }

  /// Under the card: where the text goes, or what a model is for.
  @ViewBuilder
  private var note: some View {
    if let preset = model.selectedPreset {
      Label(
        ModelStatus.privacyNote(preset, acceptsKey: model.acceptsKey), systemImage: "info.circle"
      )
      .labelStyle(NoteLabelStyle())
      .font(WindowType.footnote.font)
      .foregroundStyle(Color(Palette.textSecondary))
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 4)
    } else {
      CardFootnote(text: ModelStatus.noProviderNote)
    }
  }

  private func rowTitle(_ title: String) -> some View {
    Text(title)
      .font(WindowType.row.font)
      .foregroundStyle(Color(Palette.textPrimary))
      .fixedSize()
  }

  private func subtitle(_ details: [String]) -> String? {
    details.isEmpty ? nil : details.joined(separator: "\n")
  }

  /// A field's prompt, lighter than typed text.
  private func prompt(_ text: String) -> Text {
    Text(text).foregroundStyle(Color(Palette.textTertiary))
  }
}

// MARK: - Pieces

/// The providers as segments: 「不使用 · OpenAI · Ollama · 自定义」.
private struct ProviderPicker: View {
  let options: [String?]
  let selection: String?
  let select: (String?) -> Void

  var body: some View {
    HStack(spacing: ModelCardLayout.trackPadding) {
      ForEach(options, id: \.self) { id in
        let isSelected = id == selection
        Button {
          select(id)
        } label: {
          Text(name(id))
            .font((isSelected ? ModelCardType.segmentSelected : ModelCardType.segment).font)
            .foregroundStyle(Color(isSelected ? Palette.textPrimary : Palette.textQuiet))
            .lineLimit(1)
            .padding(.horizontal, ModelCardLayout.segmentPadding)
            .frame(height: ModelCardLayout.segmentHeight)
            .background {
              if isSelected {
                let shape = RoundedRectangle(
                  cornerRadius: ModelCardLayout.segmentRadius, style: .continuous)
                shape.fill(Color(ModelCardPalette.segmentFill))
                  .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                  .overlay(shape.strokeBorder(Color(ModelCardPalette.segmentEdge), lineWidth: 0.5))
              }
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusRing(
          RoundedRectangle(cornerRadius: ModelCardLayout.segmentRadius, style: .continuous)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .padding(ModelCardLayout.trackPadding)
    .background(
      Color(Palette.neutralTint),
      in: RoundedRectangle(cornerRadius: ModelCardLayout.trackRadius, style: .continuous)
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel(ModelText.provider)
  }

  private func name(_ id: String?) -> String {
    id == ProviderPreset.customID ? ModelCardText.custom : SettingsText.providerName(id)
  }
}

/// The test's result on a capsule, a failure on the red tint.
private struct ResultPill: View {
  let line: ModelStatusLine

  var body: some View {
    switch line.kind {
    case .busy: Pill(line.text, tone: .neutral, isBusy: true)
    case .success: Pill(line.text, symbol: "checkmark", tone: .success)
    case .warning: Pill(line.text, symbol: "exclamationmark.triangle", tone: .warning)
    case .note: Pill(line.text, tone: .neutral)
    case .failure:
      Label(line.text, systemImage: "xmark")
        .labelStyle(NoteLabelStyle())
        .font(Typography.pill.font)
        .foregroundStyle(Color(Palette.dangerOnTint))
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Color(Palette.dangerTint), in: Capsule())
        .fixedSize()
    }
  }
}

/// A status line in the window's footnote type: a note, a spinner while busy, or a symbol in
/// its tone.
private struct StatusNote: View {
  let line: ModelStatusLine

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 5) {
      switch line.kind {
      case .note: EmptyView()
      case .busy:
        Spinner(size: Typography.note.size).alignmentGuide(.firstTextBaseline) { $0.height * 0.8 }
      case .success: symbol("checkmark.circle.fill", Palette.successOnTint)
      case .warning: symbol("exclamationmark.triangle.fill", Palette.warningOnTint)
      case .failure: symbol("xmark.octagon.fill", Palette.failure)
      }
      Text(line.text)
        .lineSpacing(WindowType.footnote.lineSpacing)
        .foregroundStyle(Color(Palette.textSecondary))
        .fixedSize(horizontal: false, vertical: true)
    }
    .font(WindowType.footnote.font)
  }

  private func symbol(_ name: String, _ color: NSColor) -> some View {
    Image(systemName: name).foregroundStyle(Color(color)).accessibilityHidden(true)
  }
}

/// An icon and its text, closer together than a label's default.
private struct NoteLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 5) {
      configuration.icon.accessibilityHidden(true)
      configuration.title
    }
  }
}

extension View {
  /// A text field on the light fill of the mockup's inputs.
  fileprivate func cardField() -> some View {
    let shape = RoundedRectangle(cornerRadius: ModelCardLayout.fieldRadius, style: .continuous)
    return textFieldStyle(.plain)
      .font(ModelCardType.field.font)
      // No foreground style: it would paint the prompt like typed text.
      .padding(.horizontal, ModelCardLayout.fieldPadding)
      .frame(height: ModelCardLayout.fieldHeight)
      .background(Color(ModelCardPalette.fieldFill), in: shape)
      .overlay(shape.strokeBorder(Color(ModelCardPalette.fieldEdge), lineWidth: 0.5))
  }

  /// A pop-up menu without its label.
  fileprivate func cardMenu() -> some View {
    labelsHidden().pickerStyle(.menu).fixedSize()
  }
}

// MARK: - Tokens

private enum ModelCardLayout {
  static let rowMinHeight: CGFloat = 52
  static let rowVertical: CGFloat = 10
  static let segmentHeight: CGFloat = 26
  static let segmentPadding: CGFloat = 14
  static let segmentRadius: CGFloat = 6
  static let trackPadding: CGFloat = 2
  static let trackRadius: CGFloat = 8
  static let fieldHeight: CGFloat = 28
  static let fieldPadding: CGFloat = 10
  static let fieldRadius: CGFloat = 7
  static let fieldMinWidth: CGFloat = 120
  static let fieldMaxWidth: CGFloat = 320
  /// The model's field, beside 列出可用模型.
  static let modelMaxWidth: CGFloat = 240
  static let chevron: CGFloat = 10
}

private enum ModelCardType {
  static let segment = TextStyle(size: 13)
  static let segmentSelected = TextStyle(size: 13, weight: .semibold)
  static let field = TextStyle(size: 13.5)
}

/// The mockup's input and segment colours; the dark ones sit the same steps from the dark
/// card as the light ones from the white card.
private enum ModelCardPalette {
  static let fieldFill = color(light: (0xF7F7F9, 1), dark: (0x1F1F23, 1))
  static let fieldEdge = color(light: (0xD1D1D6, 1), dark: (0x48484E, 1))
  static let segmentFill = color(light: (0xFFFFFF, 1), dark: (0x5A5A61, 1))
  static let segmentEdge = color(light: (0x000000, 0.06), dark: (0xFFFFFF, 0.06))

  private static func color(light: (UInt32, CGFloat), dark: (UInt32, CGFloat)) -> NSColor {
    NSColor(name: nil) { appearance in
      let (hex, alpha) = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
      return NSColor(
        srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
  }
}

/// The section's wording beyond the onboarding's.
enum ModelCardText {
  static let custom = String(
    localized: "Custom", table: "Settings",
    comment: "Segment of the provider control for any OpenAI-compatible service")
  static let show = String(
    localized: "Show", table: "Settings", comment: "Button that shows the typed API key")
  static let hide = String(
    localized: "Hide", table: "Settings", comment: "Button that hides the typed API key")
  static let inKeychain = String(
    localized: "Saved in the Keychain", table: "Settings", comment: "Note under the API key field")
  static let customOptions = String(
    localized: "JSON mode, thinking, output limit", table: "Settings",
    comment: "What the collapsed Advanced row of a custom provider holds")
  static let expanded = String(
    localized: "Expanded", table: "Settings", comment: "Accessibility value of the Advanced row")
  static let collapsed = String(
    localized: "Collapsed", table: "Settings",
    comment: "Accessibility value of the Advanced row")
}
