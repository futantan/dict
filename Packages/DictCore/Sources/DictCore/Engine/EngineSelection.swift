// SPDX-License-Identifier: GPL-3.0-or-later

/// Picks the engine for a capability by the zero-configuration table of architecture 6.5.
public func engine(
  for capability: Capability, modelConfigured: Bool, appleTranslationSupportsPair: Bool
) -> Engine {
  if modelConfigured { return .model }
  switch capability {
  case .translate, .equivalents, .translateOut:
    return appleTranslationSupportsPair ? .appleTranslation : .unavailable
  case .lookup: return .dictionaryOnly
  case .proofread: return .spellChecker
  case .improve: return .unavailable
  }
}
