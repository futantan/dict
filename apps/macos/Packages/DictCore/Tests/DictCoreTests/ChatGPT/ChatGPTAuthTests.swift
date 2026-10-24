// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

struct ChatGPTAuthTests {
  private let endpoints = ChatGPTEndpoints.production
  private let attempt = AuthorizationAttempt(
    verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "st", nonce: "no",
    redirectURI: ChatGPTAuth.redirectURI(port: 1455))

  private func query(_ url: URL) -> [String: String] {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }) { first, _ in first }
  }

  @Test func codeChallengeMatchesRFC7636AppendixB() {
    #expect(
      ChatGPTAuth.codeChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
  }

  @Test func randomTokensAreURLSafeAndFresh() {
    let token = ChatGPTAuth.randomToken()
    #expect(token.count == 43)
    #expect(token.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    #expect(token != ChatGPTAuth.randomToken())
  }

  @Test(arguments: [
    "http://127.0.0.1:8767/v1", "http://127.0.0.1:8767/v1/", "http://127.0.0.1:8767",
  ])
  func theMockLivesBesideItsChatCompletions(base: String) throws {
    let mock = ChatGPTEndpoints.mock(baseURL: try #require(URL(string: base)))
    #expect(mock.issuer.absoluteString == "http://127.0.0.1:8767/auth")
    #expect(
      mock.authorize.absoluteString == "http://127.0.0.1:8767/auth/api/accounts/authorize")
    #expect(mock.token.absoluteString == "http://127.0.0.1:8767/auth/api/accounts/oauth/token")
    #expect(mock.revoke.absoluteString == "http://127.0.0.1:8767/auth/api/accounts/oauth/revoke")
    #expect(mock.api.absoluteString == "http://127.0.0.1:8767/chatgpt/v1")
  }

  @Test func theRedirectIsTheIPv4Loopback() {
    #expect(
      ChatGPTAuth.redirectURI(port: 50123).absoluteString
        == "http://127.0.0.1:50123/auth/callback")
  }

  @Test func aFirstSignInRegistersTheApp() {
    let url = attempt.url(
      endpoints, registration: ChatGPTRegistration(hostID: "urn:uuid:h"), appName: "Dict",
      idTokenHint: "ignored")
    #expect(url.absoluteString.hasPrefix("https://auth.openai.com/api/accounts/authorize?"))
    let fields = query(url)
    #expect(
      fields == [
        "response_type": "code", "client_id": "dynamic_agent_client", "agent_name_hint": "Dict",
        "ext_agent_host_id": "urn:uuid:h",
        "redirect_uri": "http://127.0.0.1:1455/auth/callback",
        "scope":
          "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
        "resource": "https://api.openai.com/v1", "state": "st", "nonce": "no",
        "code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
        "code_challenge_method": "S256",
      ])
  }

  @Test func aLaterSignInUsesTheIssuedClientAndHints() {
    let registration = ChatGPTRegistration(
      hostID: "urn:uuid:h", clientID: "oaiapp_1", email: "a+b@example.com")
    let fields = query(
      attempt.url(endpoints, registration: registration, appName: "Dict", idTokenHint: "jwt"))
    #expect(fields["client_id"] == "oaiapp_1")
    #expect(fields["agent_name_hint"] == nil)
    #expect(fields["login_hint"] == "a+b@example.com")
    #expect(fields["id_token_hint"] == "jwt")
    #expect(fields["ext_agent_host_id"] == "urn:uuid:h")
  }

  @Test func theCallbackStateIsCheckedFirst() throws {
    let base = "http://127.0.0.1:1455/auth/callback"
    #expect(throws: ChatGPTSignInError.stateMismatch) {
      try attempt.callback(URL(string: "\(base)?code=c&state=other")!)
    }
    #expect(throws: ChatGPTSignInError.stateMismatch) {
      try attempt.callback(URL(string: "\(base)?error=access_denied")!)
    }
    #expect(throws: ChatGPTSignInError.denied("access_denied")) {
      try attempt.callback(URL(string: "\(base)?error=access_denied&state=st")!)
    }
    #expect(throws: ChatGPTSignInError.missingCode) {
      try attempt.callback(URL(string: "\(base)?state=st")!)
    }
    let code = try attempt.callback(
      URL(string: "\(base)?code=c1&state=st&client_id=oaiapp_9&scope=openid%20email")!)
    #expect(code == AuthorizationCode(code: "c1", clientID: "oaiapp_9", scope: "openid email"))
  }

  @Test func theTokenRequestsAreFormsWithoutASecret() throws {
    let exchange = ChatGPTAuth.exchangeRequest(
      endpoints, code: "c/1", clientID: "oaiapp_1", attempt: attempt)
    #expect(exchange.httpMethod == "POST")
    #expect(exchange.url == endpoints.token)
    #expect(
      exchange.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    #expect(
      formFields(String(decoding: exchange.httpBody ?? Data(), as: UTF8.self)) == [
        "grant_type": "authorization_code", "client_id": "oaiapp_1", "code": "c/1",
        "code_verifier": attempt.verifier,
        "redirect_uri": "http://127.0.0.1:1455/auth/callback",
        "resource": "https://api.openai.com/v1",
      ])

    let refresh = ChatGPTAuth.refreshRequest(endpoints, refreshToken: "r", clientID: "oaiapp_1")
    #expect(
      formFields(String(decoding: refresh.httpBody ?? Data(), as: UTF8.self)) == [
        "grant_type": "refresh_token", "client_id": "oaiapp_1", "refresh_token": "r",
        "resource": "https://api.openai.com/v1",
      ])

    let revoke = ChatGPTAuth.revokeRequest(endpoints, refreshToken: "r", clientID: "oaiapp_1")
    #expect(revoke.url == endpoints.revoke)
    #expect(
      formFields(String(decoding: revoke.httpBody ?? Data(), as: UTF8.self)) == [
        "token": "r", "token_type_hint": "refresh_token", "client_id": "oaiapp_1",
      ])
  }

  @Test func tokenResponsesDecode() throws {
    let full = try TokenResponse(
      Data(
        #"{"access_token":"a","refresh_token":"r","id_token":"i","token_type":"Bearer","expires_in":3600,"scope":"openid chatgpt.tokens.use.direct","earliest_refresh_at":1800000600}"#
          .utf8))
    #expect(full.scopes == ["openid", "chatgpt.tokens.use.direct"])
    #expect(full.expiresAt(now: testNow) == testNow.addingTimeInterval(3600))
    #expect(full.earliestRefreshAt == Date(timeIntervalSince1970: 1_800_000_600))

    let iso = try TokenResponse(
      Data(#"{"access_token":"a","earliest_refresh_at":"2027-01-15T08:00:00Z"}"#.utf8))
    #expect(iso.earliestRefreshAt == Date(timeIntervalSince1970: 1_800_000_000))
    #expect(iso.scopes == nil)
    #expect(iso.expiresAt(now: testNow) == testNow.addingTimeInterval(3600))

    #expect(throws: ChatGPTSignInError.malformedTokenResponse) {
      try TokenResponse(Data(#"{"error":"invalid_grant"}"#.utf8))
    }
    #expect(ChatGPTAuth.tokenErrorCode(Data(#"{"error":"invalid_grant"}"#.utf8)) == "invalid_grant")
    #expect(
      ChatGPTAuth.tokenErrorCode(Data(#"{"error":{"code":"refresh_token_reused"}}"#.utf8))
        == "refresh_token_reused")
  }

  @Test func planUsageNeedsTheGrantedScope() {
    #expect(makeCredential().canUsePlan)
    #expect(!makeCredential(scopes: ["openid", "email", "offline_access"]).canUsePlan)
  }

  private let claims: JSONValue = [
    "iss": "https://auth.openai.com", "aud": "oaiapp_1", "sub": "user-1",
    "exp": 1_800_003_600, "nonce": "no", "email": "a@example.com",
  ]

  private func validate(_ claims: JSONValue, clientID: String = "oaiapp_1") throws {
    try IDTokenClaims(token: makeIDToken(claims)).validate(
      issuer: endpoints.issuer, clientID: clientID, nonce: "no", now: testNow)
  }

  private func replacing(_ key: String, with value: JSONValue) -> JSONValue {
    guard case .object(var members) = claims else { return claims }
    members[key] = value
    return .object(members)
  }

  @Test func idTokenClaimsAreChecked() throws {
    try validate(claims)
    try validate(replacing("aud", with: ["other", "oaiapp_1"]))
    try validate(replacing("iss", with: "https://auth.openai.com/"))
    #expect(throws: ChatGPTSignInError.invalidIDToken("iss")) {
      try validate(replacing("iss", with: "https://evil.example"))
    }
    #expect(throws: ChatGPTSignInError.invalidIDToken("aud")) {
      try validate(claims, clientID: "oaiapp_2")
    }
    #expect(throws: ChatGPTSignInError.invalidIDToken("exp")) {
      try validate(replacing("exp", with: 1_799_999_000))
    }
    #expect(throws: ChatGPTSignInError.invalidIDToken("nonce")) {
      try validate(replacing("nonce", with: "replayed"))
    }
    #expect(throws: ChatGPTSignInError.invalidIDToken("format")) {
      try IDTokenClaims(token: "not-a-jwt")
    }
    let decoded = try IDTokenClaims(token: makeIDToken(claims))
    #expect(decoded.subject == "user-1")
    #expect(decoded.email == "a@example.com")
  }

  @Test func exchangingTheCodeMakesACheckedCredential() async throws {
    let idToken = makeIDToken(claims)
    let stub = StubProtocol.register { _ in
      tokenReply([
        "access_token": "a1", "refresh_token": "r1", "id_token": .string(idToken),
        "expires_in": 3600, "scope": "openid chatgpt.tokens.use.direct",
      ])
    }
    var endpoints = stubEndpoints(auth: stub.host)
    endpoints.issuer = URL(string: "https://auth.openai.com")!
    let credential = try await exchangeAuthorizationCode(
      AuthorizationCode(code: "c1", clientID: "oaiapp_1", scope: nil), clientID: "oaiapp_1",
      attempt: attempt, endpoints: endpoints, session: stub.session, now: testNow)
    #expect(credential.accessToken == "a1")
    #expect(credential.refreshToken == "r1")
    #expect(credential.subject == "user-1")
    #expect(credential.clientID == "oaiapp_1")
    #expect(credential.canUsePlan)
    let record = try #require(StubProtocol.record(stub.host))
    #expect(record.urls.first?.path() == "/auth/api/accounts/oauth/token")
    #expect(formFields(record.forms.first ?? "")["code_verifier"] == attempt.verifier)
  }

  @Test func aRefusedCodeSaysWhy() async throws {
    let stub = StubProtocol.register { _ in tokenReply(["error": "invalid_grant"], status: 400) }
    await #expect(throws: ChatGPTSignInError.tokenRejected("invalid_grant")) {
      try await exchangeAuthorizationCode(
        AuthorizationCode(code: "c1", clientID: nil, scope: nil), clientID: "oaiapp_1",
        attempt: attempt, endpoints: stubEndpoints(auth: stub.host), session: stub.session,
        now: testNow)
    }
  }
}
