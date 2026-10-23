// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security
import Synchronization

/// Where API keys live, one per account (the provider preset id). Keys never go to
/// UserDefaults or the logs (architecture 12).
protocol SecretStore: Sendable {
  /// The stored secret, or nil when there is none.
  func secret(for account: String) throws(KeychainError) -> String?
  /// Stores `secret`; nil or empty removes the entry.
  func setSecret(_ secret: String?, for account: String) throws(KeychainError)
}

struct KeychainError: Error, Equatable {
  let status: OSStatus
}

/// Generic-password items in the login (file-based) keychain. The service is
/// `<bundle id>.model`, so the Debug and Release builds keep separate items.
struct KeychainStore: SecretStore {
  let service: String

  /// The app's own service name.
  static let app = KeychainStore(
    service: "\(Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName).model")

  private func query(_ account: String) -> [CFString: Any] {
    [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
  }

  func secret(for account: String) throws(KeychainError) -> String? {
    var query = query(account)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let data = result as? Data else { return nil }
      return String(data: data, encoding: .utf8)
    case errSecItemNotFound:
      return nil
    default:
      throw KeychainError(status: status)
    }
  }

  func setSecret(_ secret: String?, for account: String) throws(KeychainError) {
    guard let secret, !secret.isEmpty else {
      let status = SecItemDelete(query(account) as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw KeychainError(status: status)
      }
      return
    }
    let data = Data(secret.utf8)
    let update = SecItemUpdate(
      query(account) as CFDictionary, [kSecValueData: data] as CFDictionary)
    switch update {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var item = query(account)
      item[kSecValueData] = data
      let status = SecItemAdd(item as CFDictionary, nil)
      guard status == errSecSuccess else { throw KeychainError(status: status) }
    default:
      throw KeychainError(status: update)
    }
  }
}

/// Remembers what another store read, so the shortcut path reads the Keychain once per
/// account rather than on every press. Writes go through it, so a key saved in Settings
/// replaces the remembered one. A failed read is not remembered and is tried again; a
/// failed write forgets the account. A key changed by another process is seen after a
/// relaunch.
final class CachedSecretStore: SecretStore {
  /// The app's Keychain items; Settings and the translator share it.
  static let app = CachedSecretStore(KeychainStore.app)

  private let inner: any SecretStore
  /// A missing account has not been read; a nil value means there is no secret.
  private let cache = Mutex<[String: String?]>([:])

  init(_ inner: any SecretStore) {
    self.inner = inner
  }

  func secret(for account: String) throws(KeychainError) -> String? {
    if let cached = cache.withLock({ $0[account] }) { return cached }
    let secret = try inner.secret(for: account)
    cache.withLock { $0[account] = .some(secret) }
    return secret
  }

  func setSecret(_ secret: String?, for account: String) throws(KeychainError) {
    do {
      try inner.setSecret(secret, for: account)
    } catch {
      cache.withLock { $0[account] = nil }
      throw error
    }
    cache.withLock { $0[account] = .some(secret?.isEmpty == false ? secret : nil) }
  }
}

/// Keeps secrets in memory, for tests and previews.
final class InMemorySecretStore: SecretStore {
  private let secrets: Mutex<[String: String]>

  init(_ secrets: [String: String] = [:]) {
    self.secrets = Mutex(secrets)
  }

  func secret(for account: String) -> String? {
    secrets.withLock { $0[account] }
  }

  func setSecret(_ secret: String?, for account: String) {
    secrets.withLock { $0[account] = secret?.isEmpty == false ? secret : nil }
  }
}
