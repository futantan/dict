// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// A line of status in the model settings: next to the Test or List Available Models button,
/// or under the fields. Its kind picks the icon and colour.
struct ModelStatusLine: Equatable {
  enum Kind { case note, busy, success, warning, failure }

  let text: String
  let kind: Kind
}

/// One row per check of the Test button.
struct ModelCheckLine: Equatable {
  enum State { case waiting, running, passed, failed, warning }

  let title: String
  /// The result and, after a failure, a hint; empty while the check waits or runs.
  let details: [String]
  let state: State
}

/// What the model settings say, shared by the onboarding's grouped form (`ModelSections`) and
/// the settings page's cards (`ModelSettingsSection`): the same states read the same in both.
enum ModelStatus {
  /// Next to the Test button.
  static func connection(_ status: ConnectionStatus) -> ModelStatusLine {
    switch status {
    case .idle:
      ModelStatusLine(
        text: String(
          localized: "Translate a sentence and check the answers.", table: "Settings",
          comment: "Shown next to the Test button before a test"),
        kind: .note)
    case .checked(let report) where report.isRunning:
      ModelStatusLine(text: testing, kind: .busy)
    case .checked(let report) where report.isThinking == true && report.structuredOutput == .passed:
      ModelStatusLine(
        text: String(
          localized: "Dict can use this model, but it is slow.", table: "Settings",
          comment: "Test finished; every check passed but the model thinks"),
        kind: .warning)
    case .checked(let report) where report.allPassed:
      ModelStatusLine(
        text: String(
          localized: "Dict can use this model.", table: "Settings",
          comment: "Test finished and every check passed"),
        kind: .success)
    case .checked:
      ModelStatusLine(
        text: String(
          localized: "Some checks failed.", table: "Settings",
          comment: "Test finished and a check failed"),
        kind: .failure)
    case .failed(let failure):
      ModelStatusLine(text: failure.message, kind: .failure)
    }
  }

  /// The settings page's short summary of a test on a pill: 「可以使用 · 首字 0.8 秒」. Nil
  /// before a test and when none could be sent; `connection` says why.
  static func summary(_ status: ConnectionStatus) -> ModelStatusLine? {
    guard case .checked(let report) = status else { return nil }
    if report.isRunning { return ModelStatusLine(text: testing, kind: .busy) }
    guard report.allPassed else {
      return ModelStatusLine(
        text: String(
          localized: "Some checks failed", table: "Settings",
          comment: "Pill: the test finished and a check failed"),
        kind: .failure)
    }
    if report.isThinking == true {
      return ModelStatusLine(
        text: String(
          localized: "Works, but slow", table: "Settings",
          comment: "Pill: every check passed but the model thinks, so lookups are slow"),
        kind: .warning)
    }
    let seconds = report.firstContent.map(Self.seconds) ?? "–"
    return ModelStatusLine(
      text: String(
        localized: "Works · first words in \(seconds) s", table: "Settings",
        comment: "Pill: every check passed. The argument is the seconds to the first answer text"),
      kind: .success)
  }

  /// Next to the List Available Models button.
  static func modelList(_ status: ModelListStatus, preset: ProviderPreset) -> ModelStatusLine {
    switch status {
    case .idle:
      ModelStatusLine(
        text: String(
          localized: "See which models this service offers.", table: "Settings",
          comment: "Shown next to the List Available Models button before it is used"),
        kind: .note)
    case .loading:
      ModelStatusLine(
        text: String(localized: "Listing…", table: "Settings", comment: "Listing models"),
        kind: .busy)
    case .loaded(let names) where names.isEmpty:
      ModelStatusLine(
        text: preset.modelList == .ollama
          ? String(
            localized:
              "Ollama has no models yet. Download one with “ollama pull”, then list again.",
            table: "Settings", comment: "Listing Ollama models found none")
          : String(
            localized: "The service listed no models.", table: "Settings",
            comment: "Listing models found none"),
        kind: .warning)
    case .loaded(let names):
      ModelStatusLine(
        text: String(
          localized:
            "Found \(names.count) models. Choose one from the menu next to the model name.",
          table: "Settings", comment: "Listing models succeeded. The argument is how many"),
        kind: .note)
    case .failed(.model(.network)) where preset.modelList == .ollama:
      ModelStatusLine(
        text: String(
          localized: "Couldn’t reach Ollama. Check that it is running on this Mac.",
          table: "Settings", comment: "Listing Ollama models failed to connect"),
        kind: .warning)
    case .failed(let failure):
      ModelStatusLine(text: failure.message, kind: .warning)
    }
  }

  /// What to say under the fields, most important first: the Keychain failed, the fields
  /// don't make a usable endpoint yet, or where to get a key.
  enum FieldsNote: Equatable {
    case warning(String)
    case keyLink(String, URL)
  }

  @MainActor
  static func fieldsNote(_ model: SettingsModel, preset: ProviderPreset) -> FieldsNote? {
    if let status = model.keychainStatus {
      return .warning(ConnectionFailure.keychain(status).message)
    }
    // A missing key goes unsaid until something is typed: the field's prompt says it.
    if let issue = model.setupIssue, issue != .missingKey || !model.keyDraft.isEmpty {
      return .warning(issue.message)
    }
    if let help = preset.keyHelpURL, model.keyDraft.isEmpty {
      return .keyLink(
        String(
          localized: "Get an API key from \(SettingsText.providerName(preset.id))",
          table: "Settings", comment: "Link to the provider's key page. The argument is its name"),
        help)
    }
    return nil
  }

  /// Where the text goes and where the key is kept.
  static func privacyNote(_ preset: ProviderPreset, acceptsKey: Bool) -> String {
    if preset.id == ProviderPreset.customID {
      return String(
        localized:
          "Text you look up or translate is sent to the service at this base URL. Your API key is kept in the Keychain.",
        table: "Settings", comment: "Privacy note under the settings of a custom provider")
    }
    let name = SettingsText.providerName(preset.id)
    return acceptsKey
      ? String(
        localized:
          "Text you look up or translate is sent to \(name). Your API key is kept in the Keychain.",
        table: "Settings",
        comment: "Privacy note under the model settings. The argument is the provider name")
      : String(
        localized: "Text you look up or translate is sent to \(name).", table: "Settings",
        comment: "Privacy note for a provider without a key. The argument is the provider name")
  }

  /// Under the provider when none is chosen.
  static let noProviderNote = String(
    localized:
      "Dict translates with a model you choose, using your own API key or Ollama on this Mac. Correcting and polishing your writing need it too.",
    table: "Settings", comment: "Footer when no model provider is chosen")

  /// The translation, structured output and thinking checks of `report`.
  /// - Parameter hasListedModels: whether the model menu has names to choose from.
  static func checks(
    _ report: ConnectionReport, isCustom: Bool, hasListedModels: Bool
  ) -> [ModelCheckLine] {
    let translation = check(
      String(localized: "Translation", table: "Settings", comment: "Name of a test check"),
      report.translation,
      passed: String(
        localized: "The first words came after \(report.firstContent.map(seconds) ?? "–") s.",
        table: "Settings",
        comment: "Translation check passed. The argument is a number of seconds"),
      failureHint: report.suggestsModelList && hasListedModels
        ? String(
          localized: "Choose one of the models listed above.", table: "Settings",
          comment: "Hint after the service did not know the model name; its list is shown")
        : nil)
    let structured = check(
      String(
        localized: "Structured output", table: "Settings",
        comment: "Name of a test check: the model answers in a strict JSON schema"),
      report.structuredOutput,
      passed: String(
        localized: "The model answers in the requested JSON format.", table: "Settings",
        comment: "Structured output check passed"),
      failureHint: isCustom
        ? String(
          localized: "Try another JSON mode under Advanced.", table: "Settings",
          comment: "Hint after a failed structured output check of a custom provider")
        : nil)
    return [translation, structured, thinking(report)]
  }

  private static func check(
    _ title: String, _ state: CheckState, passed: String, failureHint: String?
  ) -> ModelCheckLine {
    switch state {
    case .waiting: ModelCheckLine(title: title, details: [], state: .waiting)
    case .running: ModelCheckLine(title: title, details: [], state: .running)
    case .passed: ModelCheckLine(title: title, details: [passed], state: .passed)
    case .failed(let failure):
      ModelCheckLine(
        title: title, details: [failure.message] + [failureHint].compactMap(\.self),
        state: .failed)
    case .skipped: ModelCheckLine(title: title, details: [notChecked], state: .waiting)
    }
  }

  private static func thinking(_ report: ConnectionReport) -> ModelCheckLine {
    let title = String(localized: "Thinking", table: "Settings", comment: "Name of a test check")
    switch report.isThinking {
    case .some(true):
      return ModelCheckLine(
        title: title,
        details: [
          String(
            localized: "This model is thinking, so looking up words will be slow.",
            table: "Settings", comment: "Test check: the model thinks or answers slowly")
        ],
        state: .warning)
    case .some(false):
      return ModelCheckLine(
        title: title,
        details: [
          String(
            localized: "The model answers without thinking.", table: "Settings",
            comment: "Thinking check passed")
        ],
        state: .passed)
    case nil where report.isRunning:
      return ModelCheckLine(
        title: title, details: [],
        state: report.translation == .passed ? .running : .waiting)
    case nil:
      return ModelCheckLine(title: title, details: [notChecked], state: .waiting)
    }
  }

  private static let testing = String(
    localized: "Testing…", table: "Settings", comment: "Test in progress")

  private static var notChecked: String {
    String(
      localized: "Not checked, because the translation failed.", table: "Settings",
      comment: "A test check that did not run")
  }

  private static func seconds(_ duration: Duration) -> String {
    let seconds =
      Double(duration.components.seconds)
      + Double(duration.components.attoseconds) / 1e18
    return seconds.formatted(.number.precision(.fractionLength(1)).locale(SettingsText.uiLocale))
  }
}

extension ConnectionReport {
  /// Both requests succeeded.
  fileprivate var allPassed: Bool { translation == .passed && structuredOutput == .passed }
}
