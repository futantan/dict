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
