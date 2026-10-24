// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The model the user chose (architecture 6.2). Text fields are kept as typed and checked
/// when an endpoint is built; empty means "the preset's value". The key is not here: it
/// lives in the Keychain under the provider id.
public struct ModelPreferences: Codable, Sendable, Equatable {
  /// A preset id; nil means no model, so the zero-configuration engines are used.
  public var providerID: String?
  /// Empty means the preset's default model.
  public var model: String
  /// Empty means the preset's base URL. Required for the custom provider.
  public var baseURL: String
  /// The custom provider's options (architecture 6.2); nil means the preset's value. Other
  /// providers ignore them and keep their tested preset values.
  public var thinking: ThinkingSetting?
  public var tokenLimitField: String?
  public var jsonMode: JSONMode?

  public init(providerID: String? = nil, model: String = "", baseURL: String = "") {
    self.providerID = providerID
    self.model = model
    self.baseURL = baseURL
  }

  private enum CodingKeys: String, CodingKey {
    case providerID, model, baseURL, thinking, tokenLimitField, jsonMode
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    providerID = try container.decodeIfPresent(String.self, forKey: .providerID)
    model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
    baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
    // An option this version doesn't know falls back to the preset instead of failing.
    thinking = try? container.decodeIfPresent(ThinkingSetting.self, forKey: .thinking)
    tokenLimitField = try container.decodeIfPresent(String.self, forKey: .tokenLimitField)
    jsonMode = try? container.decodeIfPresent(JSONMode.self, forKey: .jsonMode)
  }
}

/// Why the model preferences do not yet make a usable endpoint.
public enum ModelSetupIssue: Error, Sendable, Equatable {
  case noProvider
  case unknownProvider
  case missingBaseURL
  /// Not an http or https URL with a host.
  case invalidBaseURL
  /// Plain http to a host other than this Mac (architecture 12).
  case insecureBaseURL
  case missingModel
  case missingKey
  /// ChatGPT: no account is signed in.
  case notSignedIn
}

/// What a `TextModel` needs besides the key or the ChatGPT sign-in.
public struct ModelConfiguration: Sendable, Equatable {
  public var endpoint: ModelEndpoint
  /// The thinking rules of the endpoint's preset.
  public var rules: [ThinkingRule]
  /// The preset's API: a `ChatCompletionsModel`, or a `ResponsesModel` on the ChatGPT plan.
  public var wire: ModelWire

  public init(endpoint: ModelEndpoint, rules: [ThinkingRule], wire: ModelWire = .chatCompletions) {
    self.endpoint = endpoint
    self.rules = rules
    self.wire = wire
  }
}

extension ModelPreferences {
  /// The endpoint for these preferences, or the first problem with them.
  ///
  /// - Parameter hasKey: whether the Keychain holds a non-empty key for the provider, or
  ///   for ChatGPT whether an account is signed in. A custom provider without a key is
  ///   called with no authentication.
  public func configuration(
    presets: [ProviderPreset], hasKey: Bool
  ) throws(ModelSetupIssue) -> ModelConfiguration {
    let (endpoint, preset) = try resolved(presets: presets, hasKey: hasKey)
    if preset.wire == .chatGPT && !hasKey { throw .notSignedIn }
    guard !endpoint.model.isEmpty else { throw .missingModel }
    if preset.requiresKey && !hasKey { throw .missingKey }
    return ModelConfiguration(endpoint: endpoint, rules: preset.thinkingRules, wire: preset.wire)
  }

  /// The endpoint to list the provider's models from. Unlike `configuration`, it needs no
  /// model name: listing is how the user finds one.
  public func listEndpoint(
    presets: [ProviderPreset], hasKey: Bool
  ) throws(ModelSetupIssue) -> ModelEndpoint {
    let (endpoint, preset) = try resolved(presets: presets, hasKey: hasKey)
    if preset.wire == .chatGPT && !hasKey { throw .notSignedIn }
    if preset.requiresKey && !hasKey { throw .missingKey }
    return endpoint
  }

  /// The endpoint with the provider and base URL checked; the model may be empty.
  private func resolved(
    presets: [ProviderPreset], hasKey: Bool
  ) throws(ModelSetupIssue) -> (endpoint: ModelEndpoint, preset: ProviderPreset) {
    guard let providerID else { throw .noProvider }
    guard let preset = presets.first(where: { $0.id == providerID }) else {
      throw .unknownProvider
    }
    let isCustom = providerID == ProviderPreset.customID
    // The ChatGPT plan has one address; a base URL typed for another provider is ignored.
    let typedURL =
      preset.wire == .chatGPT ? "" : baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let url = typedURL.isEmpty && !isCustom ? preset.baseURL : try validatedBaseURL(typedURL)
    let typedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

    var endpoint = preset.endpoint(model: typedModel.isEmpty ? preset.defaultModel : typedModel)
    endpoint.baseURL = url
    if isCustom {
      endpoint.auth = hasKey ? preset.auth : .none
      endpoint.thinking = thinking ?? .off
      endpoint.tokenLimitField = tokenLimitField ?? preset.tokenLimitField
      endpoint.jsonMode = jsonMode ?? preset.jsonMode
    }
    return (endpoint, preset)
  }
}

/// Parses a base URL typed by the user: https anywhere, plain http only to this Mac.
public func validatedBaseURL(_ text: String) throws(ModelSetupIssue) -> URL {
  let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !text.isEmpty else { throw .missingBaseURL }
  guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
    let host = url.host(percentEncoded: false), !host.isEmpty
  else { throw .invalidBaseURL }
  switch scheme {
  case "https": return url
  case "http" where isLoopback(host): return url
  case "http": throw .insecureBaseURL
  default: throw .invalidBaseURL
  }
}

private func isLoopback(_ host: String) -> Bool {
  let host = host.lowercased()
  if host == "localhost" || host == "::1" || host == "[::1]" { return true }
  let octets = host.split(separator: ".", omittingEmptySubsequences: false)
  return octets.count == 4 && octets.first == "127"
    && octets.allSatisfy { UInt8($0) != nil }
}
