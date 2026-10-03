// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Testing

@testable import DictApp

private let liveKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]

/// The "Test" button against the real OpenAI API: two tiny calls. Skipped unless a key is
/// in the environment; the key goes to an in-memory store, never to the Keychain or disk.
///
/// `bash -c 'set -a; . ./.env; set +a; TEST_RUNNER_OPENAI_API_KEY="$OPENAI_API_KEY"
/// xcodebuild test … -only-testing:DictAppTests/SettingsLiveTests'`
@MainActor
@Suite(.enabled(if: liveKey?.isEmpty == false), .serialized)
struct SettingsLiveTests {
  private func model(key: String) throws -> SettingsModel {
    let suite = "SettingsLiveTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    let model = SettingsModel(defaults: defaults, secrets: InMemorySecretStore())
    model.selectProvider("openai")
    model.keyDraft = key
    return model
  }

  private func result(of model: SettingsModel) async -> ConnectionStatus {
    model.testConnection()
    for _ in 0..<600 where model.connection == .testing {
      try? await Task.sleep(for: .milliseconds(50))
    }
    return model.connection
  }

  @Test func realKeyConnects() async throws {
    let model = try model(key: try #require(liveKey))

    let status = await result(of: model)

    guard case .succeeded = status else {
      Issue.record("Expected success, got \(status)")
      return
    }
  }

  @Test func wrongKeyIsRejected() async throws {
    let model = try model(key: "sk-dict-settings-test-invalid")

    #expect(await result(of: model) == .failed(.model(.unauthorized)))
  }
}
