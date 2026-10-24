// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Synchronization
import Testing

@testable import DictCore

struct ChatGPTSessionTests {
  private struct Harness {
    let session: ChatGPTSession
    let store: MemoryCredentialStore
    let host: String

    var requests: Int { StubProtocol.record(host)?.forms.count ?? 0 }
    var forms: [[String: String]] { (StubProtocol.record(host)?.forms ?? []).map(formFields) }
  }

  private func harness(
    _ credential: ChatGPTCredential?, now: Date = testNow,
    reply: @escaping @Sendable (JSONValue) -> StubReply = { _ in
      tokenReply([
        "access_token": "access-2", "refresh_token": "refresh-2", "expires_in": 3600,
        "scope": "openid chatgpt.tokens.use.direct",
      ])
    }
  ) -> Harness {
    let stub = StubProtocol.register(reply)
    let store = MemoryCredentialStore(credential)
    let session = ChatGPTSession(
      endpoints: stubEndpoints(auth: stub.host), store: store, session: stub.session,
      now: { now })
    return Harness(session: session, store: store, host: stub.host)
  }

  @Test func aFreshTokenIsUsedAsItIs() async throws {
    let harness = harness(makeCredential())
    #expect(try await harness.session.accessToken() == "access-1")
    #expect(harness.requests == 0)
  }

  @Test func withoutASignInOrThePlanScopeThereIsNoToken() async throws {
    await #expect(throws: ModelError.signInRequired) {
      try await harness(nil).session.accessToken()
    }
    await #expect(throws: ModelError.planUsageNotGranted) {
      try await harness(makeCredential(scopes: ["openid"])).session.accessToken()
    }
  }

  @Test func aTokenCloseToExpiryIsRefreshedAndTheRotationSaved() async throws {
    let harness = harness(makeCredential(expiresIn: 120))
    #expect(try await harness.session.accessToken() == "access-2")
    #expect(harness.forms.first?["grant_type"] == "refresh_token")
    #expect(harness.forms.first?["refresh_token"] == "refresh-1")
    #expect(harness.forms.first?["client_id"] == "oaiapp_test")
    #expect(harness.forms.first?["scope"] == nil)
    let saved = try #require(harness.store.credential)
    #expect(saved.refreshToken == "refresh-2")
    #expect(saved.accessToken == "access-2")
    #expect(saved.expiresAt == testNow.addingTimeInterval(3600))
    #expect(saved.subject == "user-1")
    // The new token is fresh: no second refresh.
    #expect(try await harness.session.accessToken() == "access-2")
    #expect(harness.requests == 1)
  }

  @Test func notBeforeTheEarliestRefreshTimeUnlessExpired() async throws {
    let waiting = harness(
      makeCredential(expiresIn: 120, earliestRefresh: testNow.addingTimeInterval(60)))
    #expect(try await waiting.session.accessToken() == "access-1")
    #expect(waiting.requests == 0)

    let expired = harness(
      makeCredential(expiresIn: -1, earliestRefresh: testNow.addingTimeInterval(60)))
    #expect(try await expired.session.accessToken() == "access-2")
  }

  @Test func concurrentCallersShareOneRefresh() async throws {
    let harness = harness(makeCredential(expiresIn: -10))
    let tokens = try await withThrowingTaskGroup(of: String.self) { group in
      for _ in 0..<10 { group.addTask { try await harness.session.accessToken() } }
      return try await group.reduce(into: [String]()) { $0.append($1) }
    }
    #expect(tokens == Array(repeating: "access-2", count: 10))
    #expect(harness.requests == 1)
  }

  @Test func aRefusedRefreshEndsTheSignIn() async throws {
    for code in ["invalid_grant", "refresh_token_reused", "refresh_token_expired"] {
      let harness = harness(makeCredential(expiresIn: -10)) { _ in
        tokenReply(["error": .string(code)], status: 400)
      }
      await #expect(throws: ModelError.signInRequired) {
        try await harness.session.accessToken()
      }
      #expect(harness.store.credential == nil)
      await #expect(throws: ModelError.signInRequired) {
        try await harness.session.accessToken()
      }
      #expect(harness.requests == 1)
    }
  }

  @Test func aPassingFailureKeepsTheCredential() async throws {
    let server = harness(makeCredential(expiresIn: -10)) { _ in StubReply(status: 503) }
    await #expect(throws: ModelError.server(status: 503)) {
      try await server.session.accessToken()
    }
    #expect(server.store.credential == makeCredential(expiresIn: -10))

    let offline = harness(makeCredential(expiresIn: -10))
    let session = ChatGPTSession(
      endpoints: stubEndpoints(auth: "unregistered.invalid"), store: offline.store,
      session: StubProtocol.register { _ in StubReply() }.session, now: { testNow })
    await #expect(throws: ModelError.network(code: URLError.cannotFindHost.rawValue)) {
      try await session.accessToken()
    }
    #expect(offline.store.credential == makeCredential(expiresIn: -10))
  }

  @Test func aRejectedTokenIsRefreshedOnNextUse() async throws {
    let harness = harness(makeCredential())
    await harness.session.rejected("an older token")
    #expect(try await harness.session.accessToken() == "access-1")
    await harness.session.rejected("access-1")
    #expect(try await harness.session.accessToken() == "access-2")
    #expect(harness.requests == 1)
  }

  @Test func signingOutRevokesAndForgets() async throws {
    let harness = harness(makeCredential()) { _ in StubReply(status: 200, headers: [:]) }
    #expect(await harness.session.signOut())
    #expect(harness.store.credential == nil)
    let record = try #require(StubProtocol.record(harness.host))
    #expect(record.urls.first?.path() == "/auth/api/accounts/oauth/revoke")
    #expect(harness.forms.first?["token"] == "refresh-1")
    await #expect(throws: ModelError.signInRequired) {
      try await harness.session.accessToken()
    }
  }

  @Test func anUnconfirmedRevocationStillForgets() async throws {
    let harness = harness(makeCredential()) { _ in StubReply(status: 500, headers: [:]) }
    #expect(await harness.session.signOut() == false)
    #expect(harness.store.credential == nil)
  }

  @Test func aNewSignInIsSavedAndUsed() async throws {
    let harness = harness(nil)
    try await harness.session.signedIn(makeCredential(access: "fresh"))
    #expect(harness.store.credential?.accessToken == "fresh")
    #expect(try await harness.session.accessToken() == "fresh")
  }
}
