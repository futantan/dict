// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Synchronization
import Testing

@testable import DictApp

/// Nothing listens on port 9: a revocation fails at once and never leaves this Mac.
private let endpoints = ChatGPTEndpoints.mock(
  baseURL: URL(string: "http://127.0.0.1:9/v1") ?? URL(fileURLWithPath: "/"))

private func credential(email: String? = "a@example.com", scopes: Set<String>? = nil)
  -> ChatGPTCredential
{
  ChatGPTCredential(
    clientID: "oaiapp_1", subject: "user-1", email: email, idToken: "id-token",
    accessToken: "access", refreshToken: "refresh",
    // Whole seconds, which survive the JSON round trip exactly.
    expiresAt: Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 3600).rounded()),
    earliestRefreshAt: nil, scopes: scopes ?? Set(ChatGPTAuth.scopes))
}

/// What the fake browser saw and the fake token endpoint received.
private final class Browser: Sendable {
  let opened = Mutex<[URL]>([])
  let exchanged = Mutex<[(code: String, clientID: String)]>([])
}

/// Plays the browser: reads the authorization URL and requests its redirect URI, with
/// `query` (the state filled in) on the real loopback listener.
private func browser(
  _ record: Browser, query: @escaping @Sendable (_ state: String) -> String
) -> @Sendable (URL) async -> Void {
  { url in
    record.opened.withLock { $0.append(url) }
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let field = { (name: String) in items.first { $0.name == name }?.value ?? "" }
    guard let callback = URL(string: field("redirect_uri") + "?" + query(field("state"))) else {
      return
    }
    // A favicon first, as browsers do: it gets a 404 and the listener keeps waiting.
    var favicon = URLComponents(url: callback, resolvingAgainstBaseURL: false)
    favicon?.path = "/favicon.ico"
    favicon?.query = nil
    Task {
      if let icon = favicon?.url { _ = try? await URLSession.shared.data(from: icon) }
      _ = try? await URLSession.shared.data(from: callback)
    }
  }
}

private func signIn(
  _ account: ChatGPTAccount, _ record: Browser, preferredPort: UInt16 = 0,
  query: @escaping @Sendable (String) -> String
) -> ChatGPTSignIn {
  ChatGPTSignIn(
    account: account, openURL: browser(record, query: query),
    exchange: { code, clientID, _, _ in
      record.exchanged.withLock { $0.append((code.code, clientID)) }
      return credential()
    },
    timeout: .seconds(10), preferredPort: preferredPort)
}

struct ChatGPTSignInTests {
  @Test func aFirstSignInRegistersExchangesAndSaves() async throws {
    let secrets = InMemorySecretStore()
    let account = ChatGPTAccount(endpoints: endpoints, secrets: secrets)
    let record = Browser()
    let result = try await signIn(account, record) { "code=c1&state=\($0)&client_id=oaiapp_1" }
      .run()
    #expect(result.email == "a@example.com")

    let opened = try #require(record.opened.withLock { $0.first })
    let query = URLComponents(url: opened, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(query.first { $0.name == "client_id" }?.value == "dynamic_agent_client")
    let redirect = try #require(query.first { $0.name == "redirect_uri" }?.value)
    #expect(redirect.hasPrefix("http://127.0.0.1:"))
    #expect(redirect.hasSuffix("/auth/callback"))

    #expect(record.exchanged.withLock { $0.map(\.clientID) } == ["oaiapp_1"])
    let registration = try #require(try account.registrations.saved())
    #expect(registration.clientID == "oaiapp_1")
    #expect(registration.email == "a@example.com")
    #expect(registration.hostID.hasPrefix("urn:uuid:"))
    #expect(account.savedCredential == credential())
    #expect(try await account.session.accessToken() == "access")
  }

  @Test func aLaterSignInReusesTheRegistration() async throws {
    let secrets = InMemorySecretStore()
    let account = ChatGPTAccount(endpoints: endpoints, secrets: secrets)
    try account.registrations.save(
      ChatGPTRegistration(hostID: "urn:uuid:h", clientID: "oaiapp_1", email: "a@example.com"))
    let record = Browser()
    _ = try await signIn(account, record) { "code=c2&state=\($0)" }.run()
    let opened = try #require(record.opened.withLock { $0.first })
    let query = URLComponents(url: opened, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(query.first { $0.name == "client_id" }?.value == "oaiapp_1")
    #expect(query.first { $0.name == "ext_agent_host_id" }?.value == "urn:uuid:h")
    #expect(query.first { $0.name == "login_hint" }?.value == "a@example.com")
    #expect(record.exchanged.withLock { $0.map(\.code) } == ["c2"])
  }

  @Test func aForgedStateIsRefusedWithoutAnExchange() async throws {
    let account = ChatGPTAccount(endpoints: endpoints, secrets: InMemorySecretStore())
    let record = Browser()
    await #expect(throws: ChatGPTSignInError.stateMismatch) {
      try await signIn(account, record) { _ in "code=c1&state=forged&client_id=oaiapp_1" }.run()
    }
    #expect(record.exchanged.withLock { $0.isEmpty })
    #expect(account.savedCredential == nil)
  }

  @Test func aDeniedConsentStops() async throws {
    let account = ChatGPTAccount(endpoints: endpoints, secrets: InMemorySecretStore())
    await #expect(throws: ChatGPTSignInError.denied("access_denied")) {
      try await signIn(account, Browser()) { "error=access_denied&state=\($0)" }.run()
    }
  }

  @Test func anUnknownClientIsForgottenSoTheNextSignInRegisters() async throws {
    let account = ChatGPTAccount(endpoints: endpoints, secrets: InMemorySecretStore())
    try account.registrations.save(ChatGPTRegistration(hostID: "urn:uuid:h", clientID: "gone"))
    await #expect(throws: ChatGPTSignInError.denied("invalid_client")) {
      try await signIn(account, Browser()) { "error=invalid_client&state=\($0)" }.run()
    }
    let registration = try #require(try account.registrations.saved())
    #expect(registration.clientID == nil)
    #expect(registration.hostID == "urn:uuid:h")
  }

  @Test func aTakenPortFallsBackToAnother() async throws {
    let taken = try await LoopbackReceiver.start(preferring: 0)
    defer { taken.stop() }
    let other = try await LoopbackReceiver.start(preferring: taken.port)
    defer { other.stop() }
    #expect(other.port != taken.port)
    #expect(other.port != 0)
  }

  @Test func theBrowserNotComingBackTimesOut() async throws {
    let receiver = try await LoopbackReceiver.start(preferring: 0)
    defer { receiver.stop() }
    await #expect(throws: ChatGPTSignInError.timedOut) {
      try await receiver.callback(timeout: .milliseconds(50))
    }
  }

  @Test func requestLinesAreRead() {
    #expect(
      LoopbackReceiver.requestTarget(Data("GET /auth/callback?code=1 HTTP/1.1\r\nHost: x\r\n".utf8))
        == "/auth/callback?code=1")
    #expect(LoopbackReceiver.requestTarget(Data("POST /auth/callback HTTP/1.1\r\n".utf8)) == nil)
    #expect(LoopbackReceiver.requestTarget(Data("garbage".utf8)) == nil)
  }
}

struct KeychainCredentialStoreTests {
  @Test func theCredentialRoundTripsAndIsRemoved() throws {
    let secrets = InMemorySecretStore()
    let store = KeychainCredentialStore(secrets: secrets, account: "chatgpt")
    #expect(try store.load() == nil)
    try store.save(credential())
    #expect(try store.load() == credential())
    try store.save(nil)
    #expect(try store.load() == nil)
    #expect(secrets.secret(for: "chatgpt") == nil)
  }

  @Test func theRegistrationIsMadeOnceAndSurvivesSigningOut() async throws {
    let secrets = InMemorySecretStore()
    let account = ChatGPTAccount(endpoints: endpoints, secrets: secrets)
    #expect(try account.registrations.saved() == nil)
    let made = try account.registrations.load()
    #expect(try account.registrations.load() == made)
    try await account.session.signedIn(credential())
    await account.session.signOut()
    #expect(account.savedCredential == nil)
    #expect(try account.registrations.saved() == made)
  }

  @Test func theMockKeepsItsOwnAccounts() {
    let secrets = InMemorySecretStore()
    let real = ChatGPTAccount(endpoints: endpoints, secrets: secrets)
    let mock = ChatGPTAccount(endpoints: endpoints, secrets: secrets, account: "chatgpt-mock")
    #expect(real.credentials.account != mock.credentials.account)
    #expect(real.registrations.account == "chatgpt-host")
    #expect(mock.registrations.account == "chatgpt-mock-host")
  }
}
