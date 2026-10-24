// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

extension ProviderPreset {
  /// The id of the row the user fills in (any OpenAI-compatible service).
  public static let customID = "custom"
  /// The ChatGPT plan, signed in with ChatGPT.
  public static let chatGPTID = "chatgpt"

  /// The preset table shipped in `Resources/ProviderPresets.json`.
  public static func all() throws -> [ProviderPreset] {
    guard let url = Bundle.module.url(forResource: "ProviderPresets", withExtension: "json") else {
      throw CocoaError(.fileNoSuchFile)
    }
    return try JSONDecoder().decode([ProviderPreset].self, from: Data(contentsOf: url))
  }

  /// An endpoint for this preset; `model` defaults to the preset's default model.
  public func endpoint(model: String? = nil, thinking: ThinkingSetting = .off) -> ModelEndpoint {
    ModelEndpoint(
      providerID: id, baseURL: baseURL, model: model ?? defaultModel, auth: auth,
      extraHeaders: [:], thinking: thinking, jsonMode: jsonMode, tokenLimitField: tokenLimitField)
  }
}

/// The request-body fragment for `setting` on `model`, from the rule with the longest
/// matching model prefix. When the exact setting is unavailable, the other one is the closest
/// the model allows (`gpt-5-nano` cannot switch thinking off; Ollama rejects "minimal").
func thinkingFragment(
  for model: String, setting: ThinkingSetting, rules: [ThinkingRule]
) -> JSONValue? {
  let rule =
    rules
    .filter { model.hasPrefix($0.modelPrefix) }
    .max { $0.modelPrefix.count < $1.modelPrefix.count }
  guard let rule else { return nil }
  switch setting {
  case .off: return rule.off ?? rule.lowest
  case .lowest: return rule.lowest ?? rule.off
  case .providerDefault: return nil
  }
}
