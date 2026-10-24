// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Where Sign in with ChatGPT and the plan's inference live. Injectable so that tests and
/// the Debug app's mock (`scripts/fake-model.py`) stand in for OpenAI.
public struct ChatGPTEndpoints: Sendable, Equatable {
  /// The ID token's expected `iss`.
  public var issuer: URL
  public var authorize: URL
  public var token: URL
  public var revoke: URL
  /// The Responses API base; also the `resource` of every authorization and token request.
  public var api: URL

  public init(issuer: URL, authorize: URL, token: URL, revoke: URL, api: URL) {
    self.issuer = issuer
    self.authorize = authorize
    self.token = token
    self.revoke = revoke
    self.api = api
  }

  public static let production = ChatGPTEndpoints(
    issuer: url("https://auth.openai.com"),
    authorize: url("https://auth.openai.com/api/accounts/authorize"),
    token: url("https://auth.openai.com/api/accounts/oauth/token"),
    revoke: url("https://auth.openai.com/api/accounts/oauth/revoke"),
    api: url("https://api.openai.com/v1"))

  /// The mock's routes at the server of `baseURL` (for example http://127.0.0.1:8767/v1, the
  /// mock's Chat Completions base): the auth server under /auth and the plan's API under
  /// /chatgpt/v1.
  public static func mock(baseURL: URL) -> ChatGPTEndpoints {
    var root = baseURL
    if root.lastPathComponent == "v1" { root.deleteLastPathComponent() }
    let issuer = root.appending(path: "auth")
    return ChatGPTEndpoints(
      issuer: issuer,
      authorize: issuer.appending(path: "api/accounts/authorize"),
      token: issuer.appending(path: "api/accounts/oauth/token"),
      revoke: issuer.appending(path: "api/accounts/oauth/revoke"),
      api: root.appending(path: "chatgpt/v1"))
  }

  /// The usage page of the ChatGPT settings: the guidelines' "Manage usage" link.
  public static let manageUsage = url("https://chatgpt.com/settings/usage")

  private static func url(_ string: String) -> URL {
    guard let url = URL(string: string) else { preconditionFailure("bad URL literal \(string)") }
    return url
  }
}
