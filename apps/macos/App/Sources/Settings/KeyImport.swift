// SPDX-License-Identifier: GPL-3.0-or-later
//
// The debug entry point `--import-api-key <provider id> [--model <name>]`: reads an API key
// from standard input and saves it with the provider (and model) through the Settings
// window's own path, then exits. Used by scripts/import-key.sh. The Keychain item is created
// by Dict itself, so later reads by Dict never ask the user to allow access. The key is
// never written anywhere else, printed or logged. Compiled into debug builds only.

#if DEBUG
  import Foundation

  @MainActor
  enum KeyImport {
    /// Runs the import and exits when the arguments ask for it; returns otherwise.
    static func runIfRequested(arguments: [String] = CommandLine.arguments) {
      guard let index = arguments.firstIndex(of: "--import-api-key") else { return }
      exit(run(arguments: Array(arguments[(index + 1)...])))
    }

    private static func run(arguments: [String]) -> Int32 {
      guard let provider = arguments.first, !provider.hasPrefix("--") else {
        return fail("usage: --import-api-key <provider id> [--model <name>] < key")
      }
      let input = FileHandle.standardInput.readDataToEndOfFile()
      let key = String(decoding: input, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !key.isEmpty else { return fail("no key on standard input") }

      let settings = SettingsModel()
      guard settings.presets.contains(where: { $0.id == provider }) else {
        return fail("unknown provider \(provider)")
      }
      settings.selectProvider(provider)
      if let index = arguments.firstIndex(of: "--model"), arguments.indices.contains(index + 1) {
        let model = arguments[index + 1]
        settings.update { $0.model.model = model }
      }
      settings.keyDraft = key
      settings.commitKey()
      if let status = settings.keychainStatus {
        return fail("Keychain write failed: \(status)")
      }
      // Read back through the app's own store, as a translation would.
      guard (try? KeychainStore.app.secret(for: provider)) == key else {
        return fail("the key did not read back")
      }
      let model = settings.preferences.model.model
      print(
        "import-api-key: saved the key for \(provider) in service \(KeychainStore.app.service)"
          + " (\(key.count) characters); model \(model.isEmpty ? "default" : model)")
      return 0
    }

    private static func fail(_ message: String) -> Int32 {
      FileHandle.standardError.write(Data("import-api-key: \(message)\n".utf8))
      return 1
    }
  }
#endif
