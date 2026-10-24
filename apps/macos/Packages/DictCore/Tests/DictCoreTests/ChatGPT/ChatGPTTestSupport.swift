// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Synchronization

@testable import DictCore

/// Keeps the credential in memory and counts the saves.
final class MemoryCredentialStore: CredentialStore {
  private let state: Mutex<(credential: ChatGPTCredential?, saves: Int)>

  init(_ credential: ChatGPTCredential? = nil) {
    state = Mutex((credential, 0))
  }

  var credential: ChatGPTCredential? { state.withLock { $0.credential } }
  var saves: Int { state.withLock { $0.saves } }

  func load() -> ChatGPTCredential? { credential }

  func save(_ credential: ChatGPTCredential?) {
    state.withLock {
      $0.credential = credential
      $0.saves += 1
    }
  }
}

/// A compact JWT with `claims` as its payload and a dummy signature.
func makeIDToken(_ claims: JSONValue) -> String {
  let header = ChatGPTAuth.base64URL(Data(#"{"alg":"RS256","typ":"JWT"}"#.utf8))
  return "\(header).\(ChatGPTAuth.base64URL(claims.jsonData())).c2ln"
}

let testNow = Date(timeIntervalSince1970: 1_800_000_000)

func makeCredential(
  access: String = "access-1", refresh: String = "refresh-1", expiresIn: TimeInterval = 3600,
  earliestRefresh: Date? = nil, scopes: Set<String> = Set(ChatGPTAuth.scopes)
) -> ChatGPTCredential {
  ChatGPTCredential(
    clientID: "oaiapp_test", subject: "user-1", email: "a@example.com", idToken: "id",
    accessToken: access, refreshToken: refresh, expiresAt: testNow.addingTimeInterval(expiresIn),
    earliestRefreshAt: earliestRefresh, scopes: scopes)
}

/// The fields of a form-encoded body.
func formFields(_ body: String) -> [String: String] {
  var fields: [String: String] = [:]
  for pair in body.split(separator: "&") {
    let parts = pair.split(separator: "=", maxSplits: 1).map {
      String($0).removingPercentEncoding ?? String($0)
    }
    fields[parts[0]] = parts.count > 1 ? parts[1] : ""
  }
  return fields
}

/// A token-endpoint JSON reply.
func tokenReply(_ json: JSONValue, status: Int = 200) -> StubReply {
  StubReply(
    status: status, headers: ["Content-Type": "application/json"],
    chunks: [String(decoding: json.jsonData(), as: UTF8.self)])
}

/// Endpoints whose auth routes reach `auth` and whose API reaches `api` (stub hosts).
func stubEndpoints(auth: String, api: String = "api.invalid") -> ChatGPTEndpoints {
  let fallback = URL(fileURLWithPath: "/")
  var endpoints = ChatGPTEndpoints.mock(baseURL: URL(string: "https://\(auth)/v1") ?? fallback)
  endpoints.api = URL(string: "https://\(api)/v1") ?? fallback
  return endpoints
}
