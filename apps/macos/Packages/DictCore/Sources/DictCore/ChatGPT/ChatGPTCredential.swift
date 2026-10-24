// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One signed-in ChatGPT account: the tokens and what the ID token said. Kept in the
/// Keychain only (architecture 12), never logged.
public struct ChatGPTCredential: Codable, Sendable, Equatable {
  /// The client id the authorization server issued to this app on this Mac (`oaiapp_…`).
  public var clientID: String
  /// The ID token's `sub`.
  public var subject: String
  public var email: String?
  public var idToken: String
  public var accessToken: String
  public var refreshToken: String
  public var expiresAt: Date
  /// Not to be refreshed before this while the access token is still valid.
  public var earliestRefreshAt: Date?
  /// The scopes the user granted, which may be fewer than were asked for.
  public var scopes: Set<String>

  public init(
    clientID: String, subject: String, email: String?, idToken: String, accessToken: String,
    refreshToken: String, expiresAt: Date, earliestRefreshAt: Date?, scopes: Set<String>
  ) {
    self.clientID = clientID
    self.subject = subject
    self.email = email
    self.idToken = idToken
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.expiresAt = expiresAt
    self.earliestRefreshAt = earliestRefreshAt
    self.scopes = scopes
  }

  /// Whether the user let this app use their plan. Signing in alone does not: the consent
  /// page lets them leave plan usage unticked.
  public var canUsePlan: Bool { scopes.contains(ChatGPTAuth.planScope) }
}

/// What this Mac keeps across sign-ins: the host id, sent with every authorization, and the
/// issued client id with the last account's email for the next sign-in. Signing out keeps
/// it, so that signing in again reuses the registration.
public struct ChatGPTRegistration: Codable, Sendable, Equatable {
  /// `urn:uuid:<UUIDv4>`, made once per Mac; it identifies no one.
  public var hostID: String
  public var clientID: String?
  public var email: String?

  public init(hostID: String, clientID: String? = nil, email: String? = nil) {
    self.hostID = hostID
    self.clientID = clientID
    self.email = email
  }

  /// A new registration with a fresh host id.
  public static func make() -> ChatGPTRegistration {
    ChatGPTRegistration(hostID: "urn:uuid:\(UUID().uuidString.lowercased())")
  }
}

/// Where the signed-in credential is kept. `DictCore` does not touch the Keychain: the app
/// implements this on its secret store.
public protocol CredentialStore: Sendable {
  func load() throws -> ChatGPTCredential?
  /// Saves `credential`; nil removes it.
  func save(_ credential: ChatGPTCredential?) throws
}
