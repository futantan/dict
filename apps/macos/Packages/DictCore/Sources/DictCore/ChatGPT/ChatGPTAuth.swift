// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// Sign in with ChatGPT's open-source flow (docs/reviews/chatgpt-login.md 2.2–2.4): PKCE,
/// the authorization URL, the callback, the token requests and the ID token's claims. Pure
/// values and request builders; the app runs the loopback listener and the browser.
public enum ChatGPTAuth {
  /// Every scope Dict asks for. The last one lets requests use the user's plan.
  public static let scopes = [
    "openid", "profile", "email", "offline_access", "resource.invoke", planScope,
  ]
  public static let planScope = "chatgpt.tokens.use.direct"
  /// The client id of a first sign-in, which registers this app on this Mac.
  public static let dynamicClientID = "dynamic_agent_client"
  /// The callback path of the loopback redirect URI.
  public static let callbackPath = "/auth/callback"

  /// The redirect URI on `port`: always 127.0.0.1, never localhost.
  public static func redirectURI(port: UInt16) -> URL {
    var components = URLComponents()
    components.scheme = "http"
    components.host = "127.0.0.1"
    components.port = Int(port)
    components.path = callbackPath
    return components.url ?? URL(fileURLWithPath: callbackPath)
  }

  /// The S256 code challenge of `verifier` (RFC 7636 4.2).
  public static func codeChallenge(_ verifier: String) -> String {
    base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
  }

  /// `count` random bytes, base64url without padding.
  public static func randomToken(bytes count: Int = 32) -> String {
    var generator = SystemRandomNumberGenerator()
    return base64URL(
      Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
  }

  static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  static func decodeBase64URL(_ text: some StringProtocol) -> Data? {
    var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(
      of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    return Data(base64Encoded: base64)
  }
}

// MARK: - Authorization

/// The random values of one authorization attempt.
public struct AuthorizationAttempt: Sendable, Equatable {
  public var verifier: String
  public var state: String
  public var nonce: String
  public var redirectURI: URL

  public init(verifier: String, state: String, nonce: String, redirectURI: URL) {
    self.verifier = verifier
    self.state = state
    self.nonce = nonce
    self.redirectURI = redirectURI
  }

  /// Fresh values for a listener on `port`.
  public static func make(port: UInt16) -> AuthorizationAttempt {
    AuthorizationAttempt(
      verifier: ChatGPTAuth.randomToken(), state: ChatGPTAuth.randomToken(bytes: 16),
      nonce: ChatGPTAuth.randomToken(bytes: 16), redirectURI: ChatGPTAuth.redirectURI(port: port))
  }

  /// The URL to open in the browser. Without an issued client id this is a first sign-in,
  /// which registers the app with `appName`; with one, the last account's email and ID
  /// token are hints for the account to pick.
  public func url(
    _ endpoints: ChatGPTEndpoints, registration: ChatGPTRegistration, appName: String,
    idTokenHint: String? = nil
  ) -> URL {
    var items = [
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(
        name: "client_id", value: registration.clientID ?? ChatGPTAuth.dynamicClientID),
    ]
    if registration.clientID == nil {
      items.append(URLQueryItem(name: "agent_name_hint", value: appName))
    }
    items += [
      URLQueryItem(name: "ext_agent_host_id", value: registration.hostID),
      URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
      URLQueryItem(name: "scope", value: ChatGPTAuth.scopes.joined(separator: " ")),
      URLQueryItem(name: "resource", value: endpoints.api.absoluteString),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "nonce", value: nonce),
      URLQueryItem(name: "code_challenge", value: ChatGPTAuth.codeChallenge(verifier)),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
    ]
    if registration.clientID != nil {
      if let email = registration.email {
        items.append(URLQueryItem(name: "login_hint", value: email))
      }
      if let idTokenHint { items.append(URLQueryItem(name: "id_token_hint", value: idTokenHint)) }
    }
    guard var components = URLComponents(url: endpoints.authorize, resolvingAgainstBaseURL: false)
    else { return endpoints.authorize }
    components.queryItems = items
    // "+" is a space in a form-encoded query; encode it so a value keeps its plus signs.
    let query = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    components.percentEncodedQuery = query
    return components.url ?? endpoints.authorize
  }

  /// Reads the redirect the browser brought back.
  public func callback(_ url: URL) throws(ChatGPTSignInError) -> AuthorizationCode {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func value(_ name: String) -> String? {
      items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }
    guard value("state") == state else { throw .stateMismatch }
    if let error = value("error") { throw .denied(error) }
    guard let code = value("code") else { throw .missingCode }
    return AuthorizationCode(code: code, clientID: value("client_id"), scope: value("scope"))
  }
}

/// A successful callback.
public struct AuthorizationCode: Sendable, Equatable {
  public var code: String
  /// The client id issued by a first sign-in, to keep before exchanging the code.
  public var clientID: String?
  public var scope: String?
}

/// Why signing in failed.
public enum ChatGPTSignInError: Error, Sendable, Equatable {
  /// The callback's `state` is not this attempt's.
  case stateMismatch
  /// The user cancelled on the consent page (`access_denied`) or the server refused.
  case denied(String)
  case missingCode
  /// A first sign-in's callback came back without the issued client id.
  case missingClientID
  /// The token endpoint answered with an OAuth error, such as `invalid_grant`.
  case tokenRejected(String)
  case malformedTokenResponse
  /// The ID token's claims did not check out; the argument says which.
  case invalidIDToken(String)
  /// The browser never came back.
  case timedOut
}

// MARK: - Token requests

extension ChatGPTAuth {
  /// Exchanges an authorization code (form POST, no client secret).
  public static func exchangeRequest(
    _ endpoints: ChatGPTEndpoints, code: String, clientID: String, attempt: AuthorizationAttempt
  ) -> URLRequest {
    formRequest(
      endpoints.token,
      [
        ("grant_type", "authorization_code"), ("client_id", clientID), ("code", code),
        ("code_verifier", attempt.verifier), ("redirect_uri", attempt.redirectURI.absoluteString),
        ("resource", endpoints.api.absoluteString),
      ])
  }

  /// Refreshes the tokens, without `scope` so the grant stays as it is.
  public static func refreshRequest(
    _ endpoints: ChatGPTEndpoints, refreshToken: String, clientID: String
  ) -> URLRequest {
    formRequest(
      endpoints.token,
      [
        ("grant_type", "refresh_token"), ("client_id", clientID),
        ("refresh_token", refreshToken), ("resource", endpoints.api.absoluteString),
      ])
  }

  /// Revokes the refresh token on signing out.
  public static func revokeRequest(
    _ endpoints: ChatGPTEndpoints, refreshToken: String, clientID: String
  ) -> URLRequest {
    formRequest(
      endpoints.revoke,
      [
        ("token", refreshToken), ("token_type_hint", "refresh_token"), ("client_id", clientID),
      ])
  }

  static func formRequest(_ url: URL, _ fields: [(String, String)]) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = Data(
      fields.map { "\(formEncoded($0))=\(formEncoded($1))" }.joined(separator: "&").utf8)
    return request
  }

  private static func formEncoded(_ text: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
  }

  /// The OAuth error code of a failed token response: `{"error": "invalid_grant"}`, or
  /// `{"error": {"code": …}}`.
  public static func tokenErrorCode(_ data: Data) -> String? {
    guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
    return json["error"]?.stringValue ?? json["error"]?["code"]?.stringValue
  }

  /// Refresh errors after which only signing in again helps.
  public static let terminalRefreshErrors: Set<String> = [
    "invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired",
    "refresh_token_invalidated", "refresh_token_reused", "invalid_client",
  ]
}

/// A token endpoint answer.
public struct TokenResponse: Sendable, Equatable {
  public var accessToken: String
  public var refreshToken: String?
  public var idToken: String?
  public var expiresIn: Double?
  public var scopes: Set<String>?
  public var earliestRefreshAt: Date?

  /// Decodes the JSON answer. `earliest_refresh_at` is read as Unix seconds or an ISO 8601
  /// date; the documentation does not say which.
  public init(_ data: Data) throws(ChatGPTSignInError) {
    guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
      let access = json["access_token"]?.stringValue, !access.isEmpty
    else { throw .malformedTokenResponse }
    accessToken = access
    refreshToken = json["refresh_token"]?.stringValue
    idToken = json["id_token"]?.stringValue
    expiresIn = json["expires_in"]?.numberValue
    scopes = json["scope"]?.stringValue.map { Set($0.split(separator: " ").map(String.init)) }
    switch json["earliest_refresh_at"] {
    case .number(let seconds): earliestRefreshAt = Date(timeIntervalSince1970: seconds)
    case .string(let text): earliestRefreshAt = try? Date(text, strategy: .iso8601)
    default: earliestRefreshAt = nil
    }
  }

  /// When the access token expires; an hour when the answer does not say.
  public func expiresAt(now: Date) -> Date {
    now.addingTimeInterval(expiresIn ?? 3600)
  }
}

// MARK: - ID token

/// The claims Dict reads from the ID token. The token comes straight from the token endpoint
/// over TLS, so its claims are checked but its signature is not (OIDC Core 3.1.3.7 #6).
public struct IDTokenClaims: Sendable, Equatable {
  public var issuer: String
  public var audience: [String]
  public var subject: String
  public var expiresAt: Date
  public var nonce: String?
  public var email: String?

  /// Decodes the payload of a compact JWT.
  public init(token: String) throws(ChatGPTSignInError) {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3, let data = ChatGPTAuth.decodeBase64URL(parts[1]),
      let json = try? JSONDecoder().decode(JSONValue.self, from: data)
    else { throw .invalidIDToken("format") }
    guard let issuer = json["iss"]?.stringValue, let subject = json["sub"]?.stringValue,
      let exp = json["exp"]?.numberValue
    else { throw .invalidIDToken("claims") }
    self.issuer = issuer
    self.subject = subject
    expiresAt = Date(timeIntervalSince1970: exp)
    switch json["aud"] {
    case .string(let audience): self.audience = [audience]
    case .array(let values): audience = values.compactMap(\.stringValue)
    default: audience = []
    }
    nonce = json["nonce"]?.stringValue
    email = json["email"]?.stringValue
  }

  /// Checks issuer, audience, expiry and nonce.
  public func validate(
    issuer expectedIssuer: URL, clientID: String, nonce expectedNonce: String, now: Date
  ) throws(ChatGPTSignInError) {
    guard Self.sameIssuer(issuer, expectedIssuer) else { throw .invalidIDToken("iss") }
    guard audience.contains(clientID) else { throw .invalidIDToken("aud") }
    // A minute of leeway for the clocks.
    guard expiresAt.addingTimeInterval(60) > now else { throw .invalidIDToken("exp") }
    guard nonce == expectedNonce else { throw .invalidIDToken("nonce") }
  }

  private static func sameIssuer(_ claim: String, _ expected: URL) -> Bool {
    func trimmed(_ text: String) -> String { text.hasSuffix("/") ? String(text.dropLast()) : text }
    return trimmed(claim) == trimmed(expected.absoluteString)
  }
}

extension ChatGPTCredential {
  /// The credential of a code exchange, after checking its ID token.
  public init(
    exchange response: TokenResponse, clientID: String, endpoints: ChatGPTEndpoints,
    nonce: String, now: Date
  ) throws(ChatGPTSignInError) {
    guard let refresh = response.refreshToken, !refresh.isEmpty,
      let idToken = response.idToken
    else { throw .malformedTokenResponse }
    let claims = try IDTokenClaims(token: idToken)
    try claims.validate(issuer: endpoints.issuer, clientID: clientID, nonce: nonce, now: now)
    self.init(
      clientID: clientID, subject: claims.subject, email: claims.email, idToken: idToken,
      accessToken: response.accessToken, refreshToken: refresh,
      expiresAt: response.expiresAt(now: now), earliestRefreshAt: response.earliestRefreshAt,
      scopes: response.scopes ?? [])
  }

  /// This credential after a refresh: the access token, expiry, scopes and rotated refresh
  /// token replaced together; what the answer leaves out is kept.
  public func refreshed(with response: TokenResponse, now: Date) -> ChatGPTCredential {
    var next = self
    next.accessToken = response.accessToken
    next.refreshToken = response.refreshToken.flatMap { $0.isEmpty ? nil : $0 } ?? refreshToken
    next.idToken = response.idToken ?? idToken
    next.expiresAt = response.expiresAt(now: now)
    next.earliestRefreshAt = response.earliestRefreshAt
    next.scopes = response.scopes ?? scopes
    return next
  }
}

/// Exchanges the code of a callback and checks the result: the last step of signing in.
/// Throws a `ChatGPTSignInError`, or a `ModelError.network` when the server can't be reached.
public func exchangeAuthorizationCode(
  _ code: AuthorizationCode, clientID: String, attempt: AuthorizationAttempt,
  endpoints: ChatGPTEndpoints, session: URLSession = .shared, now: Date = Date()
) async throws -> ChatGPTCredential {
  let request = ChatGPTAuth.exchangeRequest(
    endpoints, code: code.code, clientID: clientID, attempt: attempt)
  let (data, status) = try await tokenEndpoint(request, session: session)
  guard (200..<300).contains(status) else {
    throw ChatGPTSignInError.tokenRejected(ChatGPTAuth.tokenErrorCode(data) ?? "HTTP \(status)")
  }
  return try ChatGPTCredential(
    exchange: TokenResponse(data), clientID: clientID, endpoints: endpoints,
    nonce: attempt.nonce, now: now)
}

/// Sends a token or revocation request; network failures become `ModelError.network`.
func tokenEndpoint(_ request: URLRequest, session: URLSession) async throws -> (Data, Int) {
  do {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw ModelError.malformedResponse }
    return (data, http.statusCode)
  } catch let error as URLError {
    if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
    throw ModelError.network(code: error.code.rawValue)
  }
}
