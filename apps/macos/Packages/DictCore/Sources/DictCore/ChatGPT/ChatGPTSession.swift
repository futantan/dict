// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Hands out access tokens for requests on the ChatGPT plan.
public protocol AccessTokenSource: Sendable {
  /// A valid access token, refreshed first when needed. Throws `ModelError.signInRequired`
  /// without a sign-in or once a refresh was refused, `ModelError.planUsageNotGranted` when
  /// the user did not grant plan usage, or the network's `ModelError`.
  func accessToken() async throws -> String
  /// The server answered 401 to `token`: the next `accessToken()` refreshes.
  func rejected(_ token: String) async
}

/// The signed-in ChatGPT account and its tokens (docs/reviews/chatgpt-login.md 4.6). One
/// instance per process: two refreshing at once would spend the same rotating refresh token
/// and end the sign-in (`refresh_token_reused`).
public actor ChatGPTSession: AccessTokenSource {
  /// How long before expiry the access token is refreshed.
  static let refreshMargin: TimeInterval = 5 * 60

  public nonisolated let endpoints: ChatGPTEndpoints
  private let store: any CredentialStore
  private let session: URLSession
  private let now: @Sendable () -> Date
  private var credential: ChatGPTCredential?
  private var isLoaded = false
  /// The access token the server rejected, refreshed on next use.
  private var rejectedToken: String?
  /// The refresh in flight, which concurrent callers share.
  private var refreshing: Task<ChatGPTCredential, Error>?

  public init(
    endpoints: ChatGPTEndpoints, store: any CredentialStore, session: URLSession = .shared,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.endpoints = endpoints
    self.store = store
    self.session = session
    self.now = now
  }

  /// The signed-in account, read from the store on first use.
  public func current() throws -> ChatGPTCredential? {
    if !isLoaded {
      credential = try store.load()
      isLoaded = true
    }
    return credential
  }

  /// Keeps the credential of a new sign-in.
  public func signedIn(_ credential: ChatGPTCredential) throws {
    try store.save(credential)
    self.credential = credential
    isLoaded = true
    rejectedToken = nil
  }

  /// Revokes the refresh token, then forgets the account. Returns whether the server
  /// confirmed the revocation; when it did not, the app is still connected in the user's
  /// ChatGPT settings until they disconnect it there.
  @discardableResult
  public func signOut() async -> Bool {
    let old = try? current()
    credential = nil
    isLoaded = true
    rejectedToken = nil
    try? store.save(nil)
    guard let old else { return true }
    let request = ChatGPTAuth.revokeRequest(
      endpoints, refreshToken: old.refreshToken, clientID: old.clientID)
    let status = try? await tokenEndpoint(request, session: session).1
    return status.map { (200..<300).contains($0) } ?? false
  }

  public func accessToken() async throws -> String {
    guard let credential = try current() else { throw ModelError.signInRequired }
    guard credential.canUsePlan else { throw ModelError.planUsageNotGranted }
    guard needsRefresh(credential) else { return credential.accessToken }
    return try await refresh(credential).accessToken
  }

  public func rejected(_ token: String) {
    if token == credential?.accessToken { rejectedToken = token }
  }

  private func needsRefresh(_ credential: ChatGPTCredential) -> Bool {
    let now = now()
    if credential.accessToken == rejectedToken || now >= credential.expiresAt { return true }
    guard now >= credential.expiresAt.addingTimeInterval(-Self.refreshMargin) else {
      return false
    }
    return credential.earliestRefreshAt.map { now >= $0 } ?? true
  }

  private func refresh(_ credential: ChatGPTCredential) async throws -> ChatGPTCredential {
    if let refreshing { return try await refreshing.value }
    let task = Task { try await performRefresh(credential) }
    refreshing = task
    defer { refreshing = nil }
    return try await task.value
  }

  /// One refresh. A refused refresh token ends the sign-in; a network or server failure
  /// keeps the credential for the next try.
  private func performRefresh(_ old: ChatGPTCredential) async throws -> ChatGPTCredential {
    let request = ChatGPTAuth.refreshRequest(
      endpoints, refreshToken: old.refreshToken, clientID: old.clientID)
    let (data, status) = try await tokenEndpoint(request, session: session)
    switch status {
    case 200..<300:
      guard let response = try? TokenResponse(data) else { throw ModelError.malformedResponse }
      // Signed out, or into another account, while the refresh was on its way.
      guard credential?.refreshToken == old.refreshToken else { throw ModelError.signInRequired }
      let next = old.refreshed(with: response, now: now())
      credential = next
      rejectedToken = nil
      // Kept in memory even when the Keychain fails, so this run goes on working.
      try? store.save(next)
      return next
    case 400, 401:
      let code = ChatGPTAuth.tokenErrorCode(data) ?? ""
      guard ChatGPTAuth.terminalRefreshErrors.contains(code) else { throw ModelError.unauthorized }
      credential = nil
      rejectedToken = nil
      try? store.save(nil)
      throw ModelError.signInRequired
    case 500...:
      throw ModelError.server(status: status)
    default:
      throw ModelError.unauthorized
    }
  }
}
