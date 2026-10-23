// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import DictCore

/// The engine table of architecture 6.5: with a model, without one but with the languages
/// installed, and with neither.
struct EngineSelectionTests {
  @Test(arguments: [
    // (capability, model configured, Apple Translation installed for the pair, expected)
    (Capability.translate, true, true, Engine.model),
    (.translate, true, false, .model),
    (.translate, false, true, .appleTranslation),
    (.translate, false, false, .unavailable),
    (.lookup, true, true, .model),
    (.lookup, false, true, .dictionaryOnly),
    (.lookup, false, false, .dictionaryOnly),
    (.equivalents, true, false, .model),
    (.equivalents, false, true, .appleTranslation),
    (.equivalents, false, false, .unavailable),
    (.proofread, true, true, .model),
    (.proofread, false, true, .spellChecker),
    (.proofread, false, false, .spellChecker),
    (.improve, true, false, .model),
    (.improve, false, true, .unavailable),
    (.translateOut, true, false, .model),
    (.translateOut, false, true, .appleTranslation),
    (.translateOut, false, false, .unavailable),
  ])
  func table(capability: Capability, model: Bool, apple: Bool, expected: Engine) {
    #expect(
      engine(for: capability, modelConfigured: model, appleTranslationInstalled: apple)
        == expected)
  }
}
