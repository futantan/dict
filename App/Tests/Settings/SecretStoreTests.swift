// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security
import Testing

@testable import DictApp

/// Runs the same contract against the in-memory store and the real Keychain. The real one
/// uses a throwaway service name and removes everything it wrote, so the user's own items
/// are never read or touched.
struct SecretStoreTests {
  private static let testService = "au.ibra.dict.tests.keychain.\(UUID().uuidString)"

  private static func removeTestItems() {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword, kSecAttrService: testService,
    ]
    SecItemDelete(query as CFDictionary)
  }

  private func checkContract(_ store: any SecretStore) throws {
    #expect(try store.secret(for: "openai") == nil)

    try store.setSecret("sk-first", for: "openai")
    #expect(try store.secret(for: "openai") == "sk-first")

    try store.setSecret("sk-second", for: "openai")
    #expect(try store.secret(for: "openai") == "sk-second")

    try store.setSecret("sk-custom", for: "custom")
    #expect(try store.secret(for: "custom") == "sk-custom")
    #expect(try store.secret(for: "openai") == "sk-second")

    try store.setSecret("", for: "openai")
    #expect(try store.secret(for: "openai") == nil)

    try store.setSecret(nil, for: "custom")
    #expect(try store.secret(for: "custom") == nil)

    // Removing what is not there is fine.
    try store.setSecret(nil, for: "custom")
  }

  @Test func inMemoryStoreFollowsTheContract() throws {
    try checkContract(InMemorySecretStore())
  }

  @Test func keychainStoreFollowsTheContract() throws {
    Self.removeTestItems()
    defer { Self.removeTestItems() }
    try checkContract(KeychainStore(service: Self.testService))
  }

  @Test func keychainStoreKeepsNonASCIIKeysIntact() throws {
    Self.removeTestItems()
    defer { Self.removeTestItems() }
    let store = KeychainStore(service: Self.testService)

    try store.setSecret("ключ-密钥-🔑", for: "custom")

    #expect(try store.secret(for: "custom") == "ключ-密钥-🔑")
  }

  @Test func appServiceIsTheBundleIdentifierDotModel() {
    #expect(KeychainStore.app.service == "\(Bundle.main.bundleIdentifier ?? "").model")
    #expect(KeychainStore.app.service.hasPrefix("au.ibra.dict"))
  }
}
