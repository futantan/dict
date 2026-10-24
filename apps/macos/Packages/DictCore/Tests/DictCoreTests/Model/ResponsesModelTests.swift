// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Synchronization
import Testing

@testable import DictCore

/// Hands out "token-1", then "token-2" once "token-1" was rejected.
private final class RotatingTokens: AccessTokenSource {
  private let state = Mutex((current: 1, rejected: [String]()))

  var rejections: [String] { state.withLock { $0.rejected } }

  func accessToken() async throws -> String { "token-\(state.withLock { $0.current })" }

  func rejected(_ token: String) async {
    state.withLock {
      $0.rejected.append(token)
      if token == "token-\($0.current)" { $0.current += 1 }
    }
  }
}

/// A refresh that takes as long as the test likes.
private final class SlowTokens: AccessTokenSource {
  private let started = Mutex(false)
  private let gate = AsyncStream<Void>.makeStream()

  var hasStarted: Bool { started.withLock { $0 } }

  func release() { gate.continuation.finish() }

  func accessToken() async throws -> String {
    started.withLock { $0 = true }
    for await _ in gate.stream {}
    return "slow"
  }

  func rejected(_ token: String) async {}
}

private struct NoSignIn: AccessTokenSource {
  func accessToken() async throws -> String { throw ModelError.signInRequired }
  func rejected(_ token: String) async {}
}

struct ResponsesModelTests {
  private let request = ModelRequest(system: "S", user: "U", output: .text, maxOutputTokens: 256)

  private func model(
    tokens: any AccessTokenSource = RotatingTokens(), clock: ManualClock = ManualClock(),
    reply: @escaping @Sendable (JSONValue) -> StubReply
  ) throws -> (ResponsesModel, String) {
    let stub = StubProtocol.register(reply)
    let rules = try #require(try ProviderPreset.all().first { $0.id == "chatgpt" }).thinkingRules
    let model = ResponsesModel(
      model: "gpt-6.1-sol", thinking: .off, rules: rules,
      endpoints: stubEndpoints(auth: "auth.invalid", api: stub.host), tokens: tokens,
      session: stub.session, clock: clock)
    return (model, stub.host)
  }

  private func collect(_ stream: AsyncThrowingStream<StreamEvent, Error>) async throws
    -> [StreamEvent]
  {
    var events: [StreamEvent] = []
    for try await event in stream { events.append(event) }
    return events
  }

  private func error(_ stream: AsyncThrowingStream<StreamEvent, Error>) async -> ModelError? {
    do {
      _ = try await collect(stream)
      return nil
    } catch {
      return error as? ModelError
    }
  }

  private static let answer = StubReply(chunks: [
    responsesEvent("response.output_text.delta", ["delta": "Hel"]),
    responsesEvent("response.output_text.delta", ["delta": "lo"]), completedEvent,
  ])

  private static func json(_ status: Int, _ body: String) -> StubReply {
    StubReply(status: status, headers: ["Content-Type": "application/json"], chunks: [body])
  }

  @Test func streamsTheAnswerWithTheBearerToken() async throws {
    let (model, host) = try model { _ in Self.answer }
    #expect(
      try await collect(model.stream(request)) == [
        .text("Hel"), .text("lo"), .finished(.complete, Usage(inputTokens: 12, outputTokens: 3)),
      ])
    let record = try #require(StubProtocol.record(host))
    #expect(record.urls.first?.path() == "/v1/responses")
    #expect(record.headers.first?["Authorization"] == "Bearer token-1")
    #expect(record.bodies.first?["store"] == false)
    #expect(record.bodies.first?["stream"] == true)
    #expect(record.bodies.first?["instructions"] == "S")
    #expect(record.bodies.first?["max_output_tokens"] == nil)
  }

  @Test func a401RefreshesAndRetriesOnce() async throws {
    let tokens = RotatingTokens()
    let calls = Mutex(0)
    let (model, host) = try model(tokens: tokens) { _ in
      calls.withLock {
        $0 += 1
        return $0
      } == 1 ? Self.json(401, #"{"detail":"expired"}"#) : Self.answer
    }
    #expect(try await collect(model.stream(request)).count == 3)
    #expect(tokens.rejections == ["token-1"])
    #expect(StubProtocol.record(host)?.headers.last?["Authorization"] == "Bearer token-2")
  }

  @Test func aSecond401IsUnauthorized() async throws {
    let tokens = RotatingTokens()
    let (model, host) = try model(tokens: tokens) { _ in Self.json(401, #"{"detail":"no"}"#) }
    #expect(await error(model.stream(request)) == .unauthorized)
    #expect(StubProtocol.record(host)?.bodies.count == 2)
  }

  @Test func planErrorsSurface() async throws {
    let (limited, _) = try model { _ in
      Self.json(429, #"{"error":{"code":"subscription_sharing_usage_limit_exceeded"}}"#)
    }
    #expect(await error(limited.stream(request)) == .planLimitReached)

    let (rejected, host) = try model { _ in
      Self.json(
        400,
        #"{"error":{"code":"subscription_sharing_unsupported_capability","message":"Unsupported","param":"reasoning.effort"}}"#
      )
    }
    #expect(
      await error(rejected.stream(request))
        == .badRequest(message: "Unsupported (reasoning.effort)"))
    // Not dropped and retried: the rejection is for a person to read.
    #expect(StubProtocol.record(host)?.bodies.count == 1)

    let (failedMidStream, _) = try model { _ in
      StubReply(chunks: [
        responsesEvent("response.output_text.delta", ["delta": "a"]),
        responsesEvent(
          "response.failed",
          ["response": ["error": ["code": "subscription_sharing_usage_limit_exceeded"]]]),
      ])
    }
    #expect(await error(failedMidStream.stream(request)) == .planLimitReached)
  }

  /// The watchdog starts once the token is there: a slow refresh is not a silent model.
  @Test func aSlowRefreshDoesNotCountAgainstTheFirstEvent() async throws {
    let tokens = SlowTokens()
    let clock = ManualClock()
    let (model, _) = try model(tokens: tokens, clock: clock) { _ in Self.answer }
    let task = Task { try await collect(model.stream(request)) }
    try await eventually { tokens.hasStarted }
    clock.advance(by: .seconds(30))
    tokens.release()
    #expect(
      try await task.value.last == .finished(.complete, Usage(inputTokens: 12, outputTokens: 3)))
  }

  @Test func withoutASignInNothingIsSent() async throws {
    let (model, host) = try model(tokens: NoSignIn()) { _ in Self.answer }
    #expect(await error(model.stream(request)) == .signInRequired)
    #expect(StubProtocol.record(host)?.bodies.isEmpty == true)
  }

  @Test func listsTheAccountsModelsInTheServersOrder() async throws {
    let stub = StubProtocol.register { _ in
      Self.json(
        200,
        #"{"models":[{"slug":"gpt-6.1-sol","display_name":"GPT-6.1 Sol","visibility":"list"},"#
          + #"{"slug":"internal","display_name":"Hidden","visibility":"hide"},"#
          + #"{"slug":"gpt-6-astra","display_name":"GPT-6 Astra","visibility":"list"}]}"#)
    }
    let names = try await listChatGPTModels(
      endpoints: stubEndpoints(auth: "auth.invalid", api: stub.host), tokens: RotatingTokens(),
      session: stub.session)
    #expect(names == ["gpt-6.1-sol", "gpt-6-astra"])
    let record = try #require(StubProtocol.record(stub.host))
    #expect(record.urls.first?.path() == "/v1/models")
    #expect(record.headers.first?["Authorization"] == "Bearer token-1")
  }
}
