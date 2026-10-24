// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// The ChatGPT credential as JSON in one secret-store account (architecture 12): the
/// Keychain in the app, memory in tests.
struct KeychainCredentialStore: CredentialStore {
  let secrets: any SecretStore
  let account: String

  func load() throws -> ChatGPTCredential? {
    guard let text = try secrets.secret(for: account) else { return nil }
    return try JSONDecoder().decode(ChatGPTCredential.self, from: Data(text.utf8))
  }

  func save(_ credential: ChatGPTCredential?) throws {
    let text = try credential.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
    try secrets.setSecret(text, for: account)
  }
}

/// This Mac's registration with Sign in with ChatGPT, beside the credential. Never removed
/// on signing out, so the host id stays and the issued client id is reused.
struct RegistrationStore: Sendable {
  let secrets: any SecretStore
  let account: String

  /// The saved registration, if any.
  func saved() throws -> ChatGPTRegistration? {
    guard let text = try secrets.secret(for: account) else { return nil }
    return try? JSONDecoder().decode(ChatGPTRegistration.self, from: Data(text.utf8))
  }

  /// The saved registration, or a new one (saved) on the first sign-in.
  func load() throws -> ChatGPTRegistration {
    if let saved = try saved() { return saved }
    let made = ChatGPTRegistration.make()
    try save(made)
    return made
  }

  func save(_ registration: ChatGPTRegistration) throws {
    try secrets.setSecret(
      String(decoding: try JSONEncoder().encode(registration), as: UTF8.self), for: account)
  }
}

/// The ChatGPT sign-in of this process: its endpoints, stores and the one `ChatGPTSession`
/// that Settings, the translator, the proofreader and the card maker share, since two
/// sessions refreshing at once would end the sign-in.
final class ChatGPTAccount: Sendable {
  /// The app's account. Under `DICT_MOCK_MODEL` (Debug only) it signs in to the mock, and
  /// keeps the mock's tokens apart from a real sign-in's.
  static let app: ChatGPTAccount = {
    let environment = ProcessInfo.processInfo.environment
    if let mock = mockModelBaseURL(environment).flatMap(URL.init(string:)) {
      return ChatGPTAccount(
        endpoints: .mock(baseURL: mock), secrets: CachedSecretStore.app, account: "chatgpt-mock")
    }
    return ChatGPTAccount(endpoints: .production, secrets: CachedSecretStore.app)
  }()

  let endpoints: ChatGPTEndpoints
  let credentials: KeychainCredentialStore
  let registrations: RegistrationStore
  let session: ChatGPTSession

  /// - Parameter account: the secret-store account of the credential; the registration
  ///   is kept under it plus "-host".
  init(
    endpoints: ChatGPTEndpoints, secrets: any SecretStore, account: String = "chatgpt",
    urlSession: URLSession = .shared
  ) {
    self.endpoints = endpoints
    credentials = KeychainCredentialStore(secrets: secrets, account: account)
    registrations = RegistrationStore(secrets: secrets, account: "\(account)-host")
    session = ChatGPTSession(endpoints: endpoints, store: credentials, session: urlSession)
  }

  /// The saved credential; nil when signed out or when the Keychain can't be read (logged).
  var savedCredential: ChatGPTCredential? {
    do {
      return try credentials.load()
    } catch {
      Log.store.error("ChatGPT credential not read: \(type(of: error), privacy: .public)")
      return nil
    }
  }

  /// The email of the last account signed in on this Mac, if any.
  var lastEmail: String? { (try? registrations.saved())??.email }
}
