// SPDX-License-Identifier: GPL-3.0-or-later

/// Picks the engine for a capability by the table of architecture 6.5. Apple's framework
/// counts only when the pair's languages happen to be installed already: Dict never asks the
/// user to download them, so a pair that is merely supported is treated as unavailable.
public func engine(
  for capability: Capability, modelConfigured: Bool, appleTranslationInstalled: Bool
) -> Engine {
  if modelConfigured { return .model }
  switch capability {
  case .translate, .equivalents, .translateOut:
    return appleTranslationInstalled ? .appleTranslation : .unavailable
  case .lookup: return .dictionaryOnly
  case .proofread: return .spellChecker
  case .improve: return .unavailable
  }
}
