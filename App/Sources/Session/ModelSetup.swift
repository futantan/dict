// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// The model to translate with, from the saved preferences and the provider's key in the
/// Keychain; nil when no usable model is set up, so Apple Translation is used (architecture
/// 6.5). The key itself is never logged.
func configuredModel(
  _ preferences: ModelPreferences, presets: [ProviderPreset], secrets: any SecretStore
) -> (configuration: ModelConfiguration, apiKey: String?)? {
  guard let providerID = preferences.providerID else { return nil }
  var key: String?
  do {
    key = try secrets.secret(for: providerID)?.trimmingCharacters(in: .whitespacesAndNewlines)
  } catch {
    Log.store.error(
      "Keychain read failed for \(providerID, privacy: .public): \(error.status, privacy: .public)")
  }
  if key?.isEmpty == true { key = nil }
  do {
    let configuration = try preferences.configuration(presets: presets, hasKey: key != nil)
    return (configuration, key)
  } catch {
    Log.model.info(
      "model not usable (\(String(describing: error), privacy: .public)); using Apple Translation")
    return nil
  }
}
