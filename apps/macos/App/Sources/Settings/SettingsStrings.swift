// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// Names and messages of the Settings window. `DictCore` returns only data; the text lives
/// in the `Settings` string table.
enum SettingsText {
  /// The UI language, so system-provided names match the rest of the window.
  static var uiLocale: Locale {
    Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
  }

  /// A language's name in the UI language, for example "Japanese" or "日语".
  static func languageName(_ identifier: String) -> String {
    switch identifier {
    case "zh-Hans":
      return String(localized: "Simplified Chinese", table: "Settings", comment: "Language name")
    case "zh-Hant":
      return String(localized: "Traditional Chinese", table: "Settings", comment: "Language name")
    default: break
    }
    let name = uiLocale.localizedString(forIdentifier: identifier) ?? identifier
    return name.prefix(1).uppercased(with: uiLocale) + name.dropFirst()
  }

  /// Provider names are localized by preset id, not taken from the preset's English name.
  static func providerName(_ id: String?) -> String {
    switch id {
    case nil:
      String(
        localized: "None", table: "Settings",
        comment: "Model provider choice meaning no model is used")
    case ProviderPreset.customID:
      String(
        localized: "Custom (OpenAI-compatible)", table: "Settings",
        comment: "Model provider choice for any service with an OpenAI-compatible API")
    case "openai": "OpenAI"
    case ProviderPreset.chatGPTID: "ChatGPT"
    case "ollama": "Ollama"
    case let id?: id
    }
  }
}

extension Accent {
  var title: String {
    switch self {
    case .american:
      String(localized: "American English", table: "Settings", comment: "Accent choice")
    case .british:
      String(localized: "British English", table: "Settings", comment: "Accent choice")
    case .australian:
      String(localized: "Australian English", table: "Settings", comment: "Accent choice")
    case .canadian:
      String(localized: "Canadian English", table: "Settings", comment: "Accent choice")
    case .indian:
      String(localized: "Indian English", table: "Settings", comment: "Accent choice")
    }
  }
}

extension ModelSetupIssue {
  var message: String {
    switch self {
    case .noProvider:
      String(
        localized: "Choose a provider.", table: "Settings",
        comment: "The model settings have no provider")
    case .unknownProvider:
      String(
        localized: "This provider is no longer available. Choose another one.",
        table: "Settings", comment: "The saved provider is not in the preset table")
    case .missingBaseURL:
      String(
        localized: "Enter the base URL of the service.", table: "Settings",
        comment: "The base URL field is empty")
    case .invalidBaseURL:
      String(
        localized: "Enter a URL that starts with https://, such as https://api.example.com/v1.",
        table: "Settings", comment: "The base URL is not a valid web address")
    case .insecureBaseURL:
      String(
        localized: "Use https://. Plain http:// is only allowed for services on this Mac.",
        table: "Settings", comment: "The base URL uses http to another computer")
    case .missingModel:
      String(
        localized: "Enter a model name.", table: "Settings",
        comment: "The model name field is empty")
    case .missingKey:
      String(
        localized: "Enter an API key.", table: "Settings", comment: "The API key field is empty")
    case .notSignedIn:
      String(
        localized: "Continue with ChatGPT to sign in.", table: "Settings",
        comment: "The ChatGPT provider has no signed-in account")
    }
  }
}

extension ConnectionFailure {
  var message: String {
    switch self {
    case .setup(let issue):
      return issue.message
    case .keychain(let status):
      return String(
        localized: "Couldn’t access the Keychain (error \(String(status))).", table: "Settings",
        comment: "Reading or saving the API key failed. The argument is an error number")
    case .other(let description):
      return description
    case .model(let error):
      return Self.message(error)
    case .structuredOutput(let error):
      return Self.message(error)
    case .listUnsupported:
      return String(
        localized: "This service doesn’t list its models. Enter the model name by hand.",
        table: "Settings", comment: "Listing models: the service answered 404 or 405")
    }
  }

  private static func message(_ error: ProofreadError) -> String {
    switch error {
    case .malformed, .edits:
      String(
        localized:
          "The model didn’t answer in the requested JSON format. Looking up words and correcting writing need it.",
        table: "Settings", comment: "Connection test: the strict JSON answer didn't decode")
    case .truncated:
      String(
        localized: "The model’s JSON answer was cut off.", table: "Settings",
        comment: "Connection test: the strict JSON answer hit the output limit")
    case .refused:
      String(
        localized: "The service’s content filter stopped the answer.", table: "Settings",
        comment: "Connection test: the strict JSON answer was refused")
    case .interrupted:
      String(
        localized: "The answer stopped before it was complete.", table: "Settings",
        comment: "Connection test: the strict JSON answer ended without a finish reason")
    }
  }

  private static func message(_ error: ModelError) -> String {
    switch error {
    case .missingKey:
      return ModelSetupIssue.missingKey.message
    case .unauthorized:
      return String(
        localized: "The service rejected the API key. Check that it is correct and active.",
        table: "Settings", comment: "Connection test: HTTP 401 or 403")
    case .modelNotFound:
      return String(
        localized: "The service has no model with this name.", table: "Settings",
        comment: "Connection test: HTTP 404")
    case .rateLimited:
      return String(
        localized:
          "The service is limiting requests, or the account is out of credit. Try again later.",
        table: "Settings", comment: "Connection test: HTTP 429")
    case .badRequest(let message):
      let detail = message.count > 240 ? message.prefix(240) + "…" : message
      return String(
        localized: "The service rejected the request: \(String(detail))", table: "Settings",
        comment: "Connection test: HTTP 400. The argument is the service's own message")
    case .server(let status):
      return String(
        localized: "The service has a problem (HTTP \(String(status))). Try again later.",
        table: "Settings", comment: "Connection test: HTTP 5xx. The argument is the status")
    case .network(let code) where code == URLError.notConnectedToInternet.rawValue:
      return String(
        localized: "This Mac is offline.", table: "Settings",
        comment: "Connection test: no network connection")
    case .network(let code):
      return String(
        localized: "Couldn’t connect to the service (error \(String(code))). Check the base URL.",
        table: "Settings", comment: "Connection test: a network error. The argument is its code")
    case .timedOut:
      return String(
        localized: "The service didn’t answer in time.", table: "Settings",
        comment: "Connection test: the request timed out")
    case .emptyResponse:
      return String(
        localized: "The service returned an empty answer.", table: "Settings",
        comment: "Connection test: no content came back")
    case .signInRequired:
      return ChatGPTText.reconnect
    case .planUsageNotGranted:
      return ChatGPTText.notGranted
    case .planNotEligible:
      return String(
        localized:
          "Your ChatGPT account can’t use its plan in this app. Your plan, workspace or region may not allow it.",
        table: "Settings", comment: "Connection test: the ChatGPT plan is not available (403)")
    case .planLimitReached:
      return String(
        localized:
          "Usage limit reached. Review your plan or this app’s limit in ChatGPT settings.",
        table: "Settings",
        comment: "Connection test: the ChatGPT plan's usage is used up (OpenAI's wording)")
    case .malformedResponse:
      return String(
        localized:
          "The service’s answer couldn’t be read. Check that the base URL is an OpenAI-compatible API.",
        table: "Settings", comment: "Connection test: the response was not Chat Completions")
    }
  }
}
