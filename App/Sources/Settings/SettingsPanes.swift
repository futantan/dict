// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import SwiftUI

// MARK: - Model

/// The model settings as a grouped form that is as tall as its content, for the settings
/// page's model section.
struct ModelForm: View {
  let model: SettingsModel

  var body: some View {
    Form {
      ModelSections(model: model)
    }
    .formStyle(.grouped)
    .scrollDisabled(true)
    .scrollContentBackground(.hidden)
    .fixedSize(horizontal: false, vertical: true)
  }
}

/// The provider, model, key and "Test" sections of a grouped form, shared by the settings
/// page and the onboarding window. The key is saved when its field loses focus or the sections go
/// away.
struct ModelSections: View {
  let model: SettingsModel

  @State private var isKeyVisible = false
  @FocusState private var isKeyFocused: Bool

  var body: some View {
    Group {
      Section {
        Picker(
          String(localized: "Provider", table: "Settings", comment: "Settings field label"),
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
          footnote(
            String(
              localized:
                "Dict translates with a model you choose, using your own API key or Ollama on this Mac. Correcting and polishing your writing need it too.",
              table: "Settings", comment: "Footer when no model provider is chosen"))
        }
      }

      if let preset = model.selectedPreset {
        Section {
          modelField(preset)
          TextField(
            String(localized: "Base URL", table: "Settings", comment: "Settings field label"),
            text: field(\.baseURL), prompt: Text(baseURLPrompt(preset)))
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
            ConnectionChecks(
              report: report, isCustom: preset.id == ProviderPreset.customID,
              hasListedModels: hasListedModels)
          }
        } footer: {
          footnote(privacyNote(preset))
        }
      }
    }
    .onChange(of: isKeyFocused) { _, focused in if !focused { model.commitKey() } }
    .onDisappear { model.commitKey() }
  }

  private func privacyNote(_ preset: ProviderPreset) -> String {
    if preset.id == ProviderPreset.customID {
      return String(
        localized:
          "Text you look up or translate is sent to the service at this base URL. Your API key is kept in the Keychain.",
        table: "Settings", comment: "Privacy note under the settings of a custom provider")
    }
    let name = SettingsText.providerName(preset.id)
    return model.acceptsKey
      ? String(
        localized:
          "Text you look up or translate is sent to \(name). Your API key is kept in the Keychain.",
        table: "Settings",
        comment: "Privacy note under the model settings. The argument is the provider name")
      : String(
        localized: "Text you look up or translate is sent to \(name).", table: "Settings",
        comment: "Privacy note for a provider without a key. The argument is the provider name")
  }

  private func field(_ keyPath: WritableKeyPath<ModelPreferences, String>) -> Binding<String> {
    Binding(
      get: { model.preferences.model[keyPath: keyPath] },
      set: { value in model.update { $0.model[keyPath: keyPath] = value } })
  }

  /// The model name as typed, with a menu of the listed models once there are some.
  private func modelField(_ preset: ProviderPreset) -> some View {
    LabeledContent {
      HStack(spacing: 6) {
        TextField(text: field(\.model), prompt: Text(modelPrompt(preset))) { EmptyView() }
          .multilineTextAlignment(.trailing)
        if case .loaded(let names) = model.modelList, !names.isEmpty {
          Menu {
            ForEach(names, id: \.self) { name in
              Button(name) { model.chooseModel(name) }
            }
          } label: {
            Image(systemName: "chevron.up.chevron.down")
          }
          .menuStyle(.borderlessButton)
          .menuIndicator(.hidden)
          .fixedSize()
          .help(
            String(
              localized: "Choose a listed model", table: "Settings",
              comment: "Help tag of the menu of listed models"))
        }
      }
    } label: {
      Text(String(localized: "Model", table: "Settings", comment: "Settings field label"))
    }
  }

  private var hasListedModels: Bool {
    guard case .loaded(let names) = model.modelList else { return false }
    return !names.isEmpty
  }

  /// "List Available Models" and what it found.
  private func listRow(_ preset: ProviderPreset) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      listStatus(preset)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button(
        String(
          localized: "List Available Models", table: "Settings",
          comment: "Button that asks the service which models it offers")
      ) {
        model.listModels()
      }
      .disabled(!model.canListModels)
    }
  }

  @ViewBuilder
  private func listStatus(_ preset: ProviderPreset) -> some View {
    switch model.modelList {
    case .idle:
      Text(
        String(
          localized: "See which models this service offers.", table: "Settings",
          comment: "Shown next to the List Available Models button before it is used")
      )
      .foregroundStyle(.secondary)
    case .loading:
      HStack(spacing: 6) {
        ProgressView().controlSize(.small)
        Text(String(localized: "Listing…", table: "Settings", comment: "Listing models"))
          .foregroundStyle(.secondary)
      }
    case .loaded(let names) where names.isEmpty:
      warningLabel(
        preset.modelList == .ollama
          ? String(
            localized:
              "Ollama has no models yet. Download one with “ollama pull”, then list again.",
            table: "Settings", comment: "Listing Ollama models found none")
          : String(
            localized: "The service listed no models.", table: "Settings",
            comment: "Listing models found none"))
    case .loaded(let names):
      Text(
        String(
          localized:
            "Found \(names.count) models. Choose one from the menu next to the model name.",
          table: "Settings", comment: "Listing models succeeded. The argument is how many")
      )
      .foregroundStyle(.secondary)
    case .failed(.model(.network)) where preset.modelList == .ollama:
      warningLabel(
        String(
          localized: "Couldn’t reach Ollama. Check that it is running on this Mac.",
          table: "Settings", comment: "Listing Ollama models failed to connect"))
    case .failed(let failure):
      warningLabel(failure.message)
    }
  }

  private func modelPrompt(_ preset: ProviderPreset) -> String {
    if !preset.defaultModel.isEmpty { return preset.defaultModel }
    return preset.id == "ollama" ? "qwen3:4b" : "model-name"
  }

  private func baseURLPrompt(_ preset: ProviderPreset) -> String {
    preset.id == ProviderPreset.customID
      ? "https://api.example.com/v1" : preset.baseURL.absoluteString
  }

  private func keyField(_ preset: ProviderPreset) -> some View {
    LabeledContent {
      HStack(spacing: 6) {
        Group {
          if isKeyVisible {
            TextField(text: keyBinding, prompt: Text(keyPrompt(preset))) { EmptyView() }
          } else {
            SecureField(text: keyBinding, prompt: Text(keyPrompt(preset))) { EmptyView() }
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
        .help(
          isKeyVisible
            ? String(localized: "Hide API key", table: "Settings", comment: "Help tag")
            : String(localized: "Show API key", table: "Settings", comment: "Help tag"))
      }
    } label: {
      Text(String(localized: "API key", table: "Settings", comment: "Settings field label"))
    }
  }

  private var keyBinding: Binding<String> {
    Binding(get: { model.keyDraft }, set: { model.keyDraft = $0 })
  }

  private func keyPrompt(_ preset: ProviderPreset) -> String {
    preset.requiresKey
      ? String(localized: "Required", table: "Settings", comment: "Placeholder of a required field")
      : String(
        localized: "Optional", table: "Settings", comment: "Placeholder of an optional field")
  }

  @ViewBuilder
  private func fieldsFooter(_ preset: ProviderPreset) -> some View {
    if let status = model.keychainStatus {
      warning(ConnectionFailure.keychain(status).message)
    } else if let issue = model.setupIssue, issue != .missingKey || !model.keyDraft.isEmpty {
      warning(issue.message)
    } else if let help = preset.keyHelpURL, model.keyDraft.isEmpty {
      Link(
        String(
          localized: "Get an API key from \(SettingsText.providerName(preset.id))",
          table: "Settings", comment: "Link to the provider's key page. The argument is its name"),
        destination: help
      )
      .font(.footnote)
      // The app's accent is the darker fill colour; a link takes the lighter text accent.
      .foregroundStyle(Color(Palette.accent))
    }
  }

  private var testRow: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      connectionStatus
        .frame(maxWidth: .infinity, alignment: .leading)
      Button(String(localized: "Test", table: "Settings", comment: "Button that tests the model")) {
        model.testConnection()
      }
      .disabled(model.connection.isTesting || model.setupIssue != nil)
    }
  }

  @ViewBuilder
  private var connectionStatus: some View {
    switch model.connection {
    case .idle:
      Text(
        String(
          localized: "Translate a sentence and check the answers.", table: "Settings",
          comment: "Shown next to the Test button before a test")
      )
      .foregroundStyle(.secondary)
    case .checked(let report) where report.isRunning:
      HStack(spacing: 6) {
        ProgressView().controlSize(.small)
        Text(String(localized: "Testing…", table: "Settings", comment: "Test in progress"))
          .foregroundStyle(.secondary)
      }
    case .checked(let report) where report.isThinking == true && report.structuredOutput == .passed:
      warningLabel(
        String(
          localized: "Dict can use this model, but it is slow.", table: "Settings",
          comment: "Test finished; every check passed but the model thinks"))
    case .checked(let report):
      if report.translation == .passed && report.structuredOutput == .passed {
        statusLabel(
          String(
            localized: "Dict can use this model.", table: "Settings",
            comment: "Test finished and every check passed"),
          symbol: "checkmark.circle.fill", color: Color(Palette.successOnTint))
      } else {
        statusLabel(
          String(
            localized: "Some checks failed.", table: "Settings",
            comment: "Test finished and a check failed"),
          symbol: "xmark.octagon.fill", color: Color(Palette.failure))
      }
    case .failed(let failure):
      statusLabel(failure.message, symbol: "xmark.octagon.fill", color: Color(Palette.failure))
        .textSelection(.enabled)
    }
  }

  private func warning(_ text: String) -> some View {
    warningLabel(text).font(.footnote)
  }
}

/// The custom provider's request options (architecture 6.2), for services that reject a
/// parameter or think by default.
private struct CustomOptionsSection: View {
  let model: SettingsModel
  let preset: ProviderPreset

  var body: some View {
    Section {
      Picker(
        String(localized: "Thinking", table: "Settings", comment: "Settings field label"),
        selection: option(\.thinking, default: .off)
      ) {
        Text(String(localized: "Off", table: "Settings", comment: "Thinking choice"))
          .tag(ThinkingSetting.off)
        Text(String(localized: "Lowest", table: "Settings", comment: "Thinking choice"))
          .tag(ThinkingSetting.lowest)
        Text(
          String(localized: "Service default", table: "Settings", comment: "Thinking choice")
        )
        .tag(ThinkingSetting.providerDefault)
      }
      Picker(
        String(
          localized: "Output limit parameter", table: "Settings", comment: "Settings field label"),
        selection: option(\.tokenLimitField, default: preset.tokenLimitField)
      ) {
        Text(verbatim: "max_tokens").tag("max_tokens")
        Text(verbatim: "max_completion_tokens").tag("max_completion_tokens")
      }
      Picker(
        String(localized: "JSON mode", table: "Settings", comment: "Settings field label"),
        selection: option(\.jsonMode, default: preset.jsonMode)
      ) {
        Text(String(localized: "Automatic", table: "Settings", comment: "JSON mode choice"))
          .tag(JSONMode.schema)
        Text(verbatim: "json_object").tag(JSONMode.object)
        Text(String(localized: "Off", table: "Settings", comment: "JSON mode choice"))
          .tag(JSONMode.none)
      }
    } header: {
      Text(String(localized: "Advanced", table: "Settings", comment: "Settings section title"))
    } footer: {
      footnote(
        String(
          localized:
            "Change these only if the test fails. Automatic asks for a strict JSON schema and leaves it out when the service rejects it.",
          table: "Settings", comment: "Footer under the custom provider's advanced options"))
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

/// One row per check of the "Test" button.
private struct ConnectionChecks: View {
  let report: ConnectionReport
  let isCustom: Bool
  /// Whether the model menu has names to choose from.
  let hasListedModels: Bool

  var body: some View {
    row(
      String(localized: "Translation", table: "Settings", comment: "Name of a test check"),
      state: report.translation, passed: firstContentText,
      failureHint: report.suggestsModelList && hasListedModels
        ? String(
          localized: "Choose one of the models listed above.", table: "Settings",
          comment: "Hint after the service did not know the model name; its list is shown")
        : nil)
    row(
      String(
        localized: "Structured output", table: "Settings",
        comment: "Name of a test check: the model answers in a strict JSON schema"),
      state: report.structuredOutput,
      passed: String(
        localized: "The model answers in the requested JSON format.", table: "Settings",
        comment: "Structured output check passed"),
      failureHint: isCustom
        ? String(
          localized: "Try another JSON mode under Advanced.", table: "Settings",
          comment: "Hint after a failed structured output check of a custom provider")
        : nil)
    thinkingRow
  }

  private var firstContentText: String {
    let seconds = report.firstContent.map(Self.seconds) ?? "–"
    return String(
      localized: "The first words came after \(seconds) s.", table: "Settings",
      comment: "Translation check passed. The argument is a number of seconds")
  }

  private func row(
    _ title: String, state: CheckState, passed: String, failureHint: String? = nil
  ) -> some View {
    LabeledContent {
      icon(state)
    } label: {
      Text(title)
      switch state {
      case .passed: Text(passed)
      case .failed(let failure):
        Text(failure.message).textSelection(.enabled)
        if let failureHint { Text(failureHint) }
      case .skipped:
        Text(
          String(
            localized: "Not checked, because the translation failed.", table: "Settings",
            comment: "A test check that did not run"))
      case .waiting, .running: EmptyView()
      }
    }
  }

  private var thinkingRow: some View {
    LabeledContent {
      switch report.isThinking {
      case .some(true):
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(
          Color(Palette.warningOnTint))
      case .some(false): icon(.passed)
      case nil:
        icon(report.isRunning ? (report.translation == .passed ? .running : .waiting) : .skipped)
      }
    } label: {
      Text(String(localized: "Thinking", table: "Settings", comment: "Name of a test check"))
      switch report.isThinking {
      case .some(true):
        Text(
          String(
            localized: "This model is thinking, so looking up words will be slow.",
            table: "Settings", comment: "Test check: the model thinks or answers slowly"))
      case .some(false):
        Text(
          String(
            localized: "The model answers without thinking.", table: "Settings",
            comment: "Thinking check passed"))
      case nil:
        if !report.isRunning {
          Text(
            String(
              localized: "Not checked, because the translation failed.", table: "Settings",
              comment: "A test check that did not run"))
        }
      }
    }
  }

  @ViewBuilder
  private func icon(_ state: CheckState) -> some View {
    switch state {
    case .waiting, .skipped:
      Image(systemName: "minus.circle").foregroundStyle(.tertiary)
    case .running:
      ProgressView().controlSize(.small)
    case .passed:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(Palette.successOnTint))
    case .failed:
      Image(systemName: "xmark.octagon.fill").foregroundStyle(Color(Palette.failure))
    }
  }

  private static func seconds(_ duration: Duration) -> String {
    let seconds =
      Double(duration.components.seconds)
      + Double(duration.components.attoseconds) / 1e18
    return seconds.formatted(.number.precision(.fractionLength(1)).locale(SettingsText.uiLocale))
  }
}

private func statusLabel(_ text: String, symbol: String, color: Color) -> some View {
  Label {
    Text(text).fixedSize(horizontal: false, vertical: true)
  } icon: {
    Image(systemName: symbol).foregroundStyle(color)
  }
}

private func warningLabel(_ text: String) -> some View {
  statusLabel(text, symbol: "exclamationmark.triangle.fill", color: Color(Palette.warningOnTint))
}

// MARK: - Shared

private func footnote(_ text: String) -> some View {
  Text(text)
    .font(.footnote)
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
}
