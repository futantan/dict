// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import SwiftUI

/// The tabs of the Settings window, in toolbar order.
enum SettingsPane: String, CaseIterable {
  case languages, model, shortcuts

  /// Every pane has this width, so the window does not jump sideways between tabs.
  static let width: CGFloat = 520

  var title: String {
    switch self {
    case .languages:
      String(localized: "Languages", table: "Settings", comment: "Settings tab title")
    case .model:
      String(localized: "Model", table: "Settings", comment: "Settings tab title")
    case .shortcuts:
      String(localized: "Shortcuts", table: "Settings", comment: "Settings tab title")
    }
  }

  var symbol: String {
    switch self {
    case .languages: "globe"
    case .model: "cpu"
    case .shortcuts: "keyboard"
    }
  }
}

// MARK: - Languages

struct LanguagesPane: View {
  let model: SettingsModel

  var body: some View {
    Form {
      Section {
        Picker(
          String(localized: "My language", table: "Settings", comment: "Settings field label"),
          selection: binding(\.myLanguage) { $0.setMyLanguage($1) }
        ) { languageOptions }
        Picker(
          String(
            localized: "Language I’m learning", table: "Settings", comment: "Settings field label"),
          selection: binding(\.learningLanguage) { $0.setLearningLanguage($1) }
        ) { languageOptions }
      } footer: {
        footnote(
          String(
            localized:
              "Text in your language is translated into the language you’re learning, and everything else into your language.",
            table: "Settings", comment: "Footer under the language pickers"))
      }

      if model.preferences.learningLanguage == "en" {
        Section {
          Picker(
            String(localized: "Accent", table: "Settings", comment: "Settings field label"),
            selection: binding(\.accent) { $0.accent = $1 }
          ) {
            ForEach(Accent.allCases, id: \.self) { Text($0.title).tag($0) }
          }
        } footer: {
          footnote(
            String(
              localized: "Used when Dict reads English words and sentences aloud.",
              table: "Settings", comment: "Footer under the accent picker"))
        }
      }
    }
    .formStyle(.grouped)
    .settingsPaneLayout()
  }

  private var languageOptions: some View {
    ForEach(Preferences.languages, id: \.self) { Text(SettingsText.languageName($0)).tag($0) }
  }

  private func binding<Value>(
    _ keyPath: KeyPath<Preferences, Value>, set: @escaping (inout Preferences, Value) -> Void
  ) -> Binding<Value> {
    Binding(
      get: { model.preferences[keyPath: keyPath] },
      set: { value in model.update { set(&$0, value) } })
  }
}

// MARK: - Model

struct ModelPane: View {
  let model: SettingsModel

  @State private var isKeyVisible = false
  @FocusState private var isKeyFocused: Bool

  var body: some View {
    Form {
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
                "Without a model, Dict translates with Apple Translation on this Mac. Correcting and polishing your writing need a model.",
              table: "Settings", comment: "Footer when no model provider is chosen"))
        }
      }

      if let preset = model.selectedPreset {
        Section {
          TextField(
            String(localized: "Model", table: "Settings", comment: "Settings field label"),
            text: field(\.model), prompt: Text(modelPrompt(preset)))
          TextField(
            String(localized: "Base URL", table: "Settings", comment: "Settings field label"),
            text: field(\.baseURL), prompt: Text(baseURLPrompt(preset)))
          if model.acceptsKey {
            keyField(preset)
          }
        } footer: {
          fieldsFooter(preset)
        }

        Section {
          testRow
        } footer: {
          footnote(privacyNote(preset))
        }
      }
    }
    .formStyle(.grouped)
    .settingsPaneLayout()
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
    }
  }

  private var testRow: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      connectionStatus
        .frame(maxWidth: .infinity, alignment: .leading)
      Button(String(localized: "Test", table: "Settings", comment: "Button that tests the model")) {
        model.testConnection()
      }
      .disabled(model.connection == .testing || model.setupIssue != nil)
    }
  }

  @ViewBuilder
  private var connectionStatus: some View {
    switch model.connection {
    case .idle:
      Text(
        String(
          localized: "Send a short request to check these settings.", table: "Settings",
          comment: "Shown next to the Test button before a test")
      )
      .foregroundStyle(.secondary)
    case .testing:
      HStack(spacing: 6) {
        ProgressView().controlSize(.small)
        Text(String(localized: "Testing…", table: "Settings", comment: "Test in progress"))
          .foregroundStyle(.secondary)
      }
    case .succeeded(let elapsed):
      Label {
        Text(
          String(
            localized: "Connected. The model answered in \(Self.seconds(elapsed)) s.",
            table: "Settings", comment: "Test succeeded. The argument is a number of seconds"))
      } icon: {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
      }
    case .failed(let failure):
      Label {
        Text(failure.message).fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
      }
      .textSelection(.enabled)
    }
  }

  private static func seconds(_ duration: Duration) -> String {
    let seconds =
      Double(duration.components.seconds)
      + Double(duration.components.attoseconds) / 1e18
    return seconds.formatted(.number.precision(.fractionLength(1)).locale(SettingsText.uiLocale))
  }

  private func warning(_ text: String) -> some View {
    Label {
      Text(text).fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
    }
    .font(.footnote)
  }
}

// MARK: - Shortcuts

struct ShortcutsPane: View {
  let center: HotkeyCenter

  var body: some View {
    Form {
      Section {
        ForEach(HotkeyRole.allCases, id: \.self) { role in
          LabeledContent {
            ShortcutRecorder(role: role, center: center)
          } label: {
            Text(role.title)
            Text(role.summary)
          }
        }
      } footer: {
        footnote(
          String(
            localized:
              "Click a shortcut and press the new keys. Press Delete to remove it, or Esc to cancel.",
            table: "Settings", comment: "Footer under the shortcut fields"))
      }
    }
    .formStyle(.grouped)
    .settingsPaneLayout()
  }
}

// MARK: - Shared

private func footnote(_ text: String) -> some View {
  Text(text)
    .font(.footnote)
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
}

extension View {
  /// A fixed-width pane that is as tall as its content.
  fileprivate func settingsPaneLayout() -> some View {
    scrollDisabled(true)
      .frame(width: SettingsPane.width)
      .fixedSize(horizontal: false, vertical: true)
  }
}
