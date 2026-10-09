// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How the API key is sent.
public enum AuthStyle: Codable, Sendable, Equatable { case bearer, header(name: String), none }

/// How much the model may think before answering.
public enum ThinkingSetting: String, Codable, Sendable { case off, lowest, providerDefault }

/// Which structured-output mode the provider supports.
public enum JSONMode: String, Codable, Sendable { case schema, object, none }

/// All non-secret configuration of one request. The key is not here: the caller reads it
/// from the Keychain and passes it separately.
public struct ModelEndpoint: Codable, Sendable, Equatable {
  /// A preset id, or "custom".
  public var providerID: String
  /// For example https://api.openai.com/v1.
  public var baseURL: URL
  public var model: String
  public var auth: AuthStyle
  public var extraHeaders: [String: String]
  public var thinking: ThinkingSetting
  public var jsonMode: JSONMode
  /// "max_completion_tokens" (OpenAI) or "max_tokens" (Ollama).
  public var tokenLimitField: String

  public init(
    providerID: String, baseURL: URL, model: String, auth: AuthStyle,
    extraHeaders: [String: String], thinking: ThinkingSetting, jsonMode: JSONMode,
    tokenLimitField: String
  ) {
    self.providerID = providerID
    self.baseURL = baseURL
    self.model = model
    self.auth = auth
    self.extraHeaders = extraHeaders
    self.thinking = thinking
    self.jsonMode = jsonMode
    self.tokenLimitField = tokenLimitField
  }
}

/// One row of the preset table, which ships as data (a JSON resource), not code.
public struct ProviderPreset: Codable, Sendable, Equatable {
  public var id: String
  public var displayName: String
  public var baseURL: URL
  public var auth: AuthStyle
  public var requiresKey: Bool
  public var keyHelpURL: URL?
  public var defaultModel: String
  public var jsonMode: JSONMode
  public var tokenLimitField: String
  /// Matched by model-name prefix.
  public var thinkingRules: [ThinkingRule]
  /// How to list the models the service offers.
  public var modelList: ModelListStyle

  public init(
    id: String, displayName: String, baseURL: URL, auth: AuthStyle, requiresKey: Bool,
    keyHelpURL: URL?, defaultModel: String, jsonMode: JSONMode, tokenLimitField: String,
    thinkingRules: [ThinkingRule], modelList: ModelListStyle = .openAI
  ) {
    self.id = id
    self.displayName = displayName
    self.baseURL = baseURL
    self.auth = auth
    self.requiresKey = requiresKey
    self.keyHelpURL = keyHelpURL
    self.defaultModel = defaultModel
    self.jsonMode = jsonMode
    self.tokenLimitField = tokenLimitField
    self.thinkingRules = thinkingRules
    self.modelList = modelList
  }
}

/// Where a provider lists its models: `GET <base URL>/models` (OpenAI compatible), or
/// Ollama's own `GET /api/tags`.
public enum ModelListStyle: String, Codable, Sendable { case openAI, ollama }

/// The request-body fragments that switch thinking off or to its lowest level.
public struct ThinkingRule: Codable, Sendable, Equatable {
  public var modelPrefix: String
  /// For example {"reasoning_effort": "none"}; nil when thinking cannot be switched off.
  public var off: JSONValue?
  /// For example {"reasoning_effort": "minimal"}.
  public var lowest: JSONValue?

  public init(modelPrefix: String, off: JSONValue?, lowest: JSONValue?) {
    self.modelPrefix = modelPrefix
    self.off = off
    self.lowest = lowest
  }
}
