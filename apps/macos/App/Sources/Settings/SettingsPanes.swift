// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import SwiftUI

// MARK: - Model

/// The provider, model, key and "Test" sections of the onboarding window's grouped form; the
/// settings page shows the same settings as cards (`ModelSettingsSection`), and both say what
/// `ModelStatus` says. The key is saved when its field loses focus or the sections go away.
struct ModelSections: View {
  let model: SettingsModel

  @State private var isKeyVisible = false
  @FocusState private var isKeyFocused: Bool

  var body: some View {
    Group {
      Section {
        Picker(
          ModelText.provider,
          selection: Binding(
            get: { model.preferences.model.providerID },
            set: { model.selectProvider($0) })
        ) {
          Text(SettingsText.providerName(nil)).tag(String?.none)
          Divider()
          ForEach(model.presets, id: \.id) { preset in
            Text(SettingsText.providerName(preset.id)).tag(Optional(preset.id))
          }
        }
      } footer: {
        if model.selectedPreset == nil {
          footnote(ModelStatus.noProviderNote)
        }
      }

      if let preset = model.selectedPreset, preset.wire == .chatGPT {
        Section {
          ChatGPTAccountRow(model: model)
          if case .signedIn(_, canUsePlan: true) = model.chatGPT {
            LabeledContent(ModelText.model) { ChatGPTModelPicker(model: model) }
          }
        }
        if case .signedIn(_, canUsePlan: true) = model.chatGPT {
          Section {
            testRow
            if case .checked(let report) = model.connection {
              ForEach(
                ModelStatus.checks(report, isCustom: false, hasListedModels: model.hasListedModels),
                id: \.title, content: checkRow)
            }
          } footer: {
            footnote(ChatGPTText.privacyNote)
          }
        }
      } else if let preset = model.selectedPreset {
        Section {
          modelField(preset)
          TextField(
            ModelText.baseURL, text: model.binding(\.baseURL),
            prompt: Text(ModelText.baseURLPrompt(preset)))
          if model.acceptsKey {
            keyField(preset)
          }
          listRow(preset)
        } footer: {
          fieldsFooter(preset)
        }

        if preset.id == ProviderPreset.customID {
          CustomOptionsSection(model: model, preset: preset)
        }

        Section {
          testRow
          if case .checked(let report) = model.connection {
            ForEach(
              ModelStatus.checks(
                report, isCustom: preset.id == ProviderPreset.customID,
                hasListedModels: model.hasListedModels),
              id: \.title, content: checkRow)
          }
        } footer: {
          footnote(ModelStatus.privacyNote(preset, acceptsKey: model.acceptsKey))
        }
      }
    }
    .onChange(of: isKeyFocused) { _, focused in if !focused { model.commitKey() } }
    .onDisappear { model.commitKey() }
    .onAppear { model.refreshChatGPT() }
    .chatGPTPlanWelcome(model)
  }

  /// The model name as typed, with a menu of the listed models once there are some.
  private func modelField(_ preset: ProviderPreset) -> some View {
    LabeledContent {
      HStack(spacing: 6) {
        TextField(text: model.binding(\.model), prompt: Text(ModelText.modelPrompt(preset))) {
          EmptyView()
        }
        .multilineTextAlignment(.trailing)
        if model.hasListedModels {
          Menu {
            ListedModels(model: model)
          } label: {
            Image(systemName: "chevron.up.chevron.down")
          }
          .menuStyle(.borderlessButton)
          .menuIndicator(.hidden)
          .fixedSize()
          .help(ModelText.chooseListedModel)
        }
      }
    } label: {
      Text(ModelText.model)
    }
  }

  /// "List Available Models" and what it found.
  private func listRow(_ preset: ProviderPreset) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      StatusLabel(line: ModelStatus.modelList(model.modelList, preset: preset))
        .frame(maxWidth: .infinity, alignment: .leading)
      Button(ModelText.listModels) {
        model.listModels()
      }
      .disabled(!model.canListModels)
    }
  }

  private func keyField(_ preset: ProviderPreset) -> some View {
    LabeledContent {
      HStack(spacing: 6) {
        Group {
          if isKeyVisible {
            TextField(text: model.keyBinding, prompt: Text(ModelText.keyPrompt(preset))) {
              EmptyView()
            }
          } else {
            SecureField(text: model.keyBinding, prompt: Text(ModelText.keyPrompt(preset))) {
              EmptyView()
            }
          }
        }
        .multilineTextAlignment(.trailing)
        .focused($isKeyFocused)
        .onSubmit { model.commitKey() }

        Button {
          isKeyVisible.toggle()
        } label: {
          Image(systemName: isKeyVisible ? "eye.slash" : "eye")
            .frame(width: 16)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(isKeyVisible ? ModelText.hideKeyHelp : ModelText.showKeyHelp)
      }
    } label: {
      Text(ModelText.apiKey)
    }
  }

  @ViewBuilder
  private func fieldsFooter(_ preset: ProviderPreset) -> some View {
    switch ModelStatus.fieldsNote(model, preset: preset) {
    case .warning(let text):
      StatusLabel(line: ModelStatusLine(text: text, kind: .warning)).font(.footnote)
    case .keyLink(let title, let url):
      Link(title, destination: url)
        .font(.footnote)
        // The app's accent is the darker fill colour; a link takes the lighter text accent.
        .foregroundStyle(Color(Palette.accent))
    case nil:
      EmptyView()
    }
  }

  private var testRow: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      StatusLabel(line: ModelStatus.connection(model.connection))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button(ModelText.test) {
        model.testConnection()
      }
      .disabled(!model.canTest)
    }
  }

  private func checkRow(_ check: ModelCheckLine) -> some View {
    LabeledContent {
      CheckIcon(state: check.state)
    } label: {
      Text(check.title)
      ForEach(check.details, id: \.self) { Text($0).textSelection(.enabled) }
    }
  }
}

/// The custom provider's request options (architecture 6.2), for services that reject a
/// parameter or think by default.
private struct CustomOptionsSection: View {
  let model: SettingsModel
  let preset: ProviderPreset

  var body: some View {
    Section {
      let options = CustomOptions(model: model, preset: preset)
      options.thinking
      options.outputLimit
      options.jsonMode
    } header: {
      Text(ModelText.advanced)
    } footer: {
      footnote(ModelText.advancedNote)
    }
  }
}

/// The custom provider's thinking, output limit and JSON mode pickers, shared by the
/// onboarding's form and the settings page's 高级 rows.
@MainActor
struct CustomOptions {
  let model: SettingsModel
  let preset: ProviderPreset

  var thinking: some View {
    Picker(ModelText.thinking, selection: option(\.thinking, default: .off)) {
      Text(String(localized: "Off", table: "Settings", comment: "Thinking choice"))
        .tag(ThinkingSetting.off)
      Text(String(localized: "Lowest", table: "Settings", comment: "Thinking choice"))
        .tag(ThinkingSetting.lowest)
      Text(String(localized: "Service default", table: "Settings", comment: "Thinking choice"))
        .tag(ThinkingSetting.providerDefault)
    }
  }

  var outputLimit: some View {
    Picker(
      ModelText.outputLimit, selection: option(\.tokenLimitField, default: preset.tokenLimitField)
    ) {
      Text(verbatim: "max_tokens").tag("max_tokens")
      Text(verbatim: "max_completion_tokens").tag("max_completion_tokens")
    }
  }

  var jsonMode: some View {
    Picker(ModelText.jsonMode, selection: option(\.jsonMode, default: preset.jsonMode)) {
      Text(String(localized: "Automatic", table: "Settings", comment: "JSON mode choice"))
        .tag(JSONMode.schema)
      Text(verbatim: "json_object").tag(JSONMode.object)
      Text(String(localized: "Off", table: "Settings", comment: "JSON mode choice"))
        .tag(JSONMode.none)
    }
  }

  private func option<Value: Hashable>(
    _ keyPath: WritableKeyPath<ModelPreferences, Value?>, default fallback: Value
  ) -> Binding<Value> {
    Binding(
      get: { model.preferences.model[keyPath: keyPath] ?? fallback },
      set: { value in model.update { $0.model[keyPath: keyPath] = value } })
  }
}

/// The names "List Available Models" found, as menu items that choose one.
struct ListedModels: View {
  let model: SettingsModel

  var body: some View {
    if case .loaded(let names) = model.modelList {
      ForEach(names, id: \.self) { name in
        Button(name) { model.chooseModel(name) }
      }
    }
  }
}

/// A status line with its icon: a note in secondary text, a spinner while busy, or a
/// coloured symbol.
struct StatusLabel: View {
  let line: ModelStatusLine

  var body: some View {
    switch line.kind {
    case .note:
      Text(line.text).foregroundStyle(.secondary)
    case .busy:
      HStack(spacing: 6) {
        ProgressView().controlSize(.small)
        Text(line.text).foregroundStyle(.secondary)
      }
    case .success:
      label(symbol: "checkmark.circle.fill", color: Color(Palette.successOnTint))
    case .warning:
      label(symbol: "exclamationmark.triangle.fill", color: Color(Palette.warningOnTint))
    case .failure:
      label(symbol: "xmark.octagon.fill", color: Color(Palette.failure))
    }
  }

  private func label(symbol: String, color: Color) -> some View {
    Label {
      Text(line.text).fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: symbol).foregroundStyle(color)
    }
  }
}

/// The icon of one check of the Test button.
struct CheckIcon: View {
  let state: ModelCheckLine.State

  var body: some View {
    switch state {
    case .waiting:
      Image(systemName: "minus.circle").foregroundStyle(.tertiary)
    case .running:
      ProgressView().controlSize(.small)
    case .passed:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(Palette.successOnTint))
    case .failed:
      Image(systemName: "xmark.octagon.fill").foregroundStyle(Color(Palette.failure))
    case .warning:
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(Color(Palette.warningOnTint))
    }
  }
}

// MARK: - Shared

/// The field labels and prompts of the model settings, in both places they are shown.
enum ModelText {
  static let provider = String(
    localized: "Provider", table: "Settings", comment: "Settings field label")
  static let model = String(localized: "Model", table: "Settings", comment: "Settings field label")
  static let baseURL = String(
    localized: "Base URL", table: "Settings", comment: "Settings field label")
  static let apiKey = String(
    localized: "API key", table: "Settings", comment: "Settings field label")
  static let listModels = String(
    localized: "List Available Models", table: "Settings",
    comment: "Button that asks the service which models it offers")
  static let chooseListedModel = String(
    localized: "Choose a listed model", table: "Settings",
    comment: "Help tag of the menu of listed models")
  static let test = String(
    localized: "Test", table: "Settings", comment: "Button that tests the model")
  static let showKeyHelp = String(localized: "Show API key", table: "Settings", comment: "Help tag")
  static let hideKeyHelp = String(localized: "Hide API key", table: "Settings", comment: "Help tag")
  static let advanced = String(
    localized: "Advanced", table: "Settings", comment: "Settings section title")
  static let advancedNote = String(
    localized:
      "Change these only if the test fails. Automatic asks for a strict JSON schema and leaves it out when the service rejects it.",
    table: "Settings", comment: "Footer under the custom provider's advanced options")
  static let thinking = String(
    localized: "Thinking", table: "Settings", comment: "Settings field label")
  static let outputLimit = String(
    localized: "Output limit parameter", table: "Settings", comment: "Settings field label")
  static let jsonMode = String(
    localized: "JSON mode", table: "Settings", comment: "Settings field label")

  static func modelPrompt(_ preset: ProviderPreset) -> String {
    if !preset.defaultModel.isEmpty { return preset.defaultModel }
    return preset.id == "ollama" ? "qwen3:4b" : "model-name"
  }

  static func baseURLPrompt(_ preset: ProviderPreset) -> String {
    preset.id == ProviderPreset.customID
      ? "https://api.example.com/v1" : preset.baseURL.absoluteString
  }

  static func keyPrompt(_ preset: ProviderPreset) -> String {
    preset.requiresKey
      ? String(localized: "Required", table: "Settings", comment: "Placeholder of a required field")
      : String(
        localized: "Optional", table: "Settings", comment: "Placeholder of an optional field")
  }
}

extension SettingsModel {
  /// A text field of the model preferences, saved on every change.
  func binding(_ keyPath: WritableKeyPath<ModelPreferences, String>) -> Binding<String> {
    Binding(
      get: { self.preferences.model[keyPath: keyPath] },
      set: { value in self.update { $0.model[keyPath: keyPath] = value } })
  }

  /// The key field, saved by `commitKey`.
  var keyBinding: Binding<String> {
    Binding(get: { self.keyDraft }, set: { self.keyDraft = $0 })
  }

  /// Whether the model menu has names to choose from.
  var hasListedModels: Bool {
    guard case .loaded(let names) = modelList else { return false }
    return !names.isEmpty
  }

  /// Whether the Test button is on: not while testing, nor while the fields are incomplete.
  var canTest: Bool { !connection.isTesting && setupIssue == nil }
}

private func footnote(_ text: String) -> some View {
  Text(text)
    .font(.footnote)
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
}
