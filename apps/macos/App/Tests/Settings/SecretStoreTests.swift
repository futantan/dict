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

  @Test func cachedStoreFollowsTheContract() throws {
    try checkContract(CachedSecretStore(InMemorySecretStore()))
  }

  @Test func cachedStoreReadsEachAccountOnce() throws {
    let inner = CountingSecretStore(["openai": "sk-saved"])
    let store = CachedSecretStore(inner)

    #expect(try store.secret(for: "openai") == "sk-saved")
    #expect(try store.secret(for: "openai") == "sk-saved")
    #expect(try store.secret(for: "custom") == nil)
    #expect(try store.secret(for: "custom") == nil)

    #expect(inner.reads == ["openai", "custom"])
  }

  @Test func savingAKeyReplacesTheCachedOne() throws {
    let inner = CountingSecretStore(["openai": "sk-old"])
    let store = CachedSecretStore(inner)
    #expect(try store.secret(for: "openai") == "sk-old")

    try store.setSecret("sk-new", for: "openai")
    #expect(try store.secret(for: "openai") == "sk-new")
    try store.setSecret(nil, for: "openai")
    #expect(try store.secret(for: "openai") == nil)

    #expect(inner.reads == ["openai"])
  }

  @Test func failedReadsAreTriedAgain() throws {
    let inner = CountingSecretStore(["openai": "sk-saved"])
    inner.failure = KeychainError(status: errSecInteractionNotAllowed)
    let store = CachedSecretStore(inner)

    #expect(throws: KeychainError(status: errSecInteractionNotAllowed)) {
      try store.secret(for: "openai")
    }
    inner.failure = nil
    #expect(try store.secret(for: "openai") == "sk-saved")
  }

  @Test func failedWritesForgetTheCachedKey() throws {
    let inner = CountingSecretStore(["openai": "sk-old"])
    let store = CachedSecretStore(inner)
    #expect(try store.secret(for: "openai") == "sk-old")

    inner.failure = KeychainError(status: errSecWrPerm)
    #expect(throws: KeychainError(status: errSecWrPerm)) {
      try store.setSecret("sk-new", for: "openai")
    }
    inner.failure = nil
    #expect(try store.secret(for: "openai") == "sk-old")
    #expect(inner.reads == ["openai", "openai"])
  }

  @Test func appServiceIsTheBundleIdentifierDotModel() {
    #expect(KeychainStore.app.service == "\(Bundle.main.bundleIdentifier ?? "").model")
    #expect(KeychainStore.app.service.hasPrefix("au.ibra.dict"))
  }
}

/// An in-memory store that records reads and can be made to fail.
private final class CountingSecretStore: SecretStore, @unchecked Sendable {
  private var secrets: [String: String]
  private(set) var reads: [String] = []
  var failure: KeychainError?

  init(_ secrets: [String: String]) { self.secrets = secrets }

  func secret(for account: String) throws(KeychainError) -> String? {
    if let failure { throw failure }
    reads.append(account)
    return secrets[account]
  }

  func setSecret(_ secret: String?, for account: String) throws(KeychainError) {
    if let failure { throw failure }
    secrets[account] = secret?.isEmpty == false ? secret : nil
  }
}
