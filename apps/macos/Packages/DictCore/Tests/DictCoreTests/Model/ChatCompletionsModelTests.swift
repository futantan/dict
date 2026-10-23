// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

struct ChatCompletionsModelTests {
  private static let key = "sk-test-0123456789"
  private let request = ModelRequest(
    system: "S", user: "U", output: .text, maxOutputTokens: 256)

  private struct Harness {
    let model: ChatCompletionsModel
    let host: String
    let clock: ManualClock
    let dropped: DroppedParameters
  }

  private func harness(
    auth: AuthStyle = .bearer, apiKey: String? = key, model: String = "gpt-6-luna",
    dropped: DroppedParameters = DroppedParameters(),
    reply: @escaping @Sendable (JSONValue) -> StubReply
  ) throws -> Harness {
    let stub = StubProtocol.register(reply)
    var preset = try #require(try ProviderPreset.all().first)
    preset.baseURL = stub.baseURL
    preset.auth = auth
    let clock = ManualClock()
    let endpoint = preset.endpoint(model: model)
    let model = ChatCompletionsModel(
      endpoint: endpoint, rules: preset.thinkingRules, apiKey: apiKey, session: stub.session,
      clock: clock, dropped: dropped)
    return Harness(model: model, host: stub.host, clock: clock, dropped: dropped)
  }

  private func collect(_ stream: AsyncThrowingStream<StreamEvent, Error>) async throws
    -> [StreamEvent]
  {
    var events: [StreamEvent] = []
    for try await event in stream { events.append(event) }
    return events
  }

  private func error(of stream: AsyncThrowingStream<StreamEvent, Error>) async -> ModelError? {
    do {
      _ = try await collect(stream)
      return nil
    } catch {
      return error as? ModelError
    }
  }

  @Test func streamsTextAndSendsTheRequest() async throws {
    let harness = try harness { _ in
      StubReply(chunks: [delta("Hel"), delta("lo"), stopChunk, usageChunk, done])
    }
    let events = try await collect(harness.model.stream(request))
    #expect(
      events == [
        .text("Hel"), .text("lo"), .finished(.complete, Usage(inputTokens: 12, outputTokens: 3)),
      ])

    let record = try #require(StubProtocol.record(harness.host))
    #expect(record.bodies.count == 1)
    #expect(record.bodies.first?["reasoning_effort"] == "none")
    #expect(record.bodies.first?["stream"] == true)
    #expect(record.headers.first?["Authorization"] == "Bearer \(Self.key)")
  }

  @Test func customHeaderAuth() async throws {
    let harness = try harness(auth: .header(name: "x-api-key")) { _ in
      StubReply(chunks: [delta("a"), stopChunk, done])
    }
    _ = try await collect(harness.model.stream(request))
    let headers = try #require(StubProtocol.record(harness.host)?.headers.first)
    #expect(headers["x-api-key"] == Self.key)
    #expect(headers["Authorization"] == nil)
  }

  @Test func missingKeyFailsWithoutARequest() async throws {
    let harness = try harness(apiKey: nil) { _ in StubReply() }
    #expect(await error(of: harness.model.stream(request)) == .missingKey)
    #expect(StubProtocol.record(harness.host)?.bodies.isEmpty == true)
  }

  @Test func noKeyNeededForAuthNone() async throws {
    let harness = try harness(auth: .none, apiKey: nil) { _ in
      StubReply(chunks: [delta("a"), stopChunk, done])
    }
    #expect(try await collect(harness.model.stream(request)).first == .text("a"))
  }

  @Test(arguments: [
    (401, ModelError.unauthorized), (403, .unauthorized), (404, .modelNotFound),
    (500, .server(status: 500)), (503, .server(status: 503)),
  ])
  func httpErrorsMap(status: Int, expected: ModelError) async throws {
    let harness = try harness { _ in
      StubReply(
        status: status, headers: ["Content-Type": "application/json"],
        chunks: [#"{"error":{"message":"nope"}}"#])
    }
    #expect(await error(of: harness.model.stream(request)) == expected)
    #expect(StubProtocol.record(harness.host)?.bodies.count == 1)
  }

  @Test func rateLimitCarriesRetryAfter() async throws {
    let harness = try harness { _ in
      StubReply(status: 429, headers: ["Retry-After": "7"], chunks: ["{}"])
    }
    #expect(
      await error(of: harness.model.stream(request)) == .rateLimited(retryAfter: .seconds(7)))
    #expect(StubProtocol.record(harness.host)?.bodies.count == 1)
  }

  @Test func badRequestMasksTheKeyAndDoesNotRetryUnrelatedErrors() async throws {
    let harness = try harness { _ in
      StubReply(
        status: 400, headers: ["Content-Type": "application/json"],
        chunks: [#"{"error":{"message":"messages too long for \#(Self.key)"}}"#])
    }
    #expect(
      await error(of: harness.model.stream(request))
        == .badRequest(message: "messages too long for ••••"))
    #expect(StubProtocol.record(harness.host)?.bodies.count == 1)
  }

  @Test func rejectedParameterIsDroppedRetriedOnceAndRemembered() async throws {
    let dropped = DroppedParameters()
    let reply: @Sendable (JSONValue) -> StubReply = { body in
      guard body["reasoning_effort"] == nil else {
        return StubReply(
          status: 400, headers: ["Content-Type": "application/json"],
          chunks: [
            #"{"error":{"message":"Unsupported value: 'none'","param":"reasoning_effort"}}"#
          ])
      }
      return StubReply(chunks: [delta("ok"), stopChunk, done])
    }
    let first = try harness(model: "gpt-4.1-mini", dropped: dropped, reply: reply)
    #expect(try await collect(first.model.stream(request)).first == .text("ok"))
    let bodies = try #require(StubProtocol.record(first.host)?.bodies)
    #expect(bodies.count == 2)
    #expect(bodies.last?["reasoning_effort"] == nil)
    #expect(bodies.last?["max_completion_tokens"] == 256)

    // A later call to the same endpoint and model leaves the parameter out from the start.
    #expect(dropped.names(for: first.model.endpoint) == ["reasoning_effort"])
    _ = try await collect(first.model.stream(request))
    let later = try #require(StubProtocol.record(first.host)?.bodies)
    #expect(later.count == 3)
    #expect(later.last?["reasoning_effort"] == nil)
  }

  @Test func parameterNamedOnlyInTheMessageIsDropped() async throws {
    let reply: @Sendable (JSONValue) -> StubReply = { body in
      guard body["stream_options"] == nil else {
        return StubReply(
          status: 400, chunks: [#"{"error":{"message":"unknown field stream_options"}}"#])
      }
      return StubReply(chunks: [delta("ok"), stopChunk, done])
    }
    let harness = try harness(reply: reply)
    #expect(try await collect(harness.model.stream(request)).first == .text("ok"))
    #expect(StubProtocol.record(harness.host)?.bodies.count == 2)
  }

  @Test func retriesOnlyOnce() async throws {
    let harness = try harness { _ in
      StubReply(
        status: 400, chunks: [#"{"error":{"message":"bad response_format and stream_options"}}"#])
    }
    #expect(await error(of: harness.model.stream(request)) != nil)
    #expect(StubProtocol.record(harness.host)?.bodies.count == 2)
  }

  @Test func nonStreamResponseIsParsedAsJSON() async throws {
    let harness = try harness { _ in
      StubReply(
        headers: ["Content-Type": "application/json"],
        chunks: [#"{"choices":[{"message":{"content":"Hi"},"finish_reason":"length"}]}"#])
    }
    #expect(
      try await collect(harness.model.stream(request)) == [.text("Hi"), .finished(.truncated, nil)])
    #expect(StubProtocol.record(harness.host)?.bodies.count == 1)
  }

  @Test func silentServerTimesOutBeforeFirstEvent() async throws {
    let harness = try harness { _ in StubReply(finishes: false) }
    let stream = harness.model.stream(request)
    async let failure = error(of: stream)
    try await harness.clock.waitForSleeper()
    harness.clock.advance(by: .seconds(10))
    #expect(await failure == .timedOut(.firstEvent))
  }

  @Test func stalledStreamTimesOutWhenIdle() async throws {
    let harness = try harness { _ in StubReply(chunks: [delta("a")], finishes: false) }
    var iterator = harness.model.stream(request).makeAsyncIterator()
    #expect(try await iterator.next() == .text("a"))
    try await harness.clock.waitForSleeper()
    harness.clock.advance(by: .seconds(15))
    do {
      _ = try await iterator.next()
      Issue.record("expected a timeout")
    } catch {
      #expect(error as? ModelError == .timedOut(.idle))
    }
  }

  @Test func cancellingTheConsumerCancelsTheRequest() async throws {
    let harness = try harness { _ in StubReply(chunks: [delta("a")], finishes: false) }
    let stream = harness.model.stream(request)
    let consumer = Task { try await collect(stream) }
    try await eventually { StubProtocol.record(harness.host)?.bodies.count == 1 }
    consumer.cancel()
    try await eventually { (StubProtocol.record(harness.host)?.stopped ?? 0) > 0 }
    _ = try? await consumer.value
  }
}

struct WatchdogTests {
  private let timeouts = ModelTimeouts.standard

  @Test func firstEvent() async throws {
    let clock = ManualClock()
    let watchdog = Watchdog(clock: clock, timeouts: timeouts)
    async let stage = watchdog.expiry()
    try await clock.waitForSleeper()
    clock.advance(by: .seconds(9))
    #expect(clock.sleeperCount == 1)
    clock.advance(by: .seconds(1))
    #expect(try await stage == .firstEvent)
  }

  @Test func eventsKeepItAliveUntilIdle() async throws {
    let clock = ManualClock()
    let watchdog = Watchdog(clock: clock, timeouts: timeouts)
    async let stage = watchdog.expiry()
    try await clock.waitForSleeper()
    clock.advance(by: .seconds(5))
    watchdog.feed()  // t = 5: idle deadline is now 20.
    clock.advance(by: .seconds(5))  // t = 10: wakes, sees the event, sleeps until 20.
    try await clock.waitForSleeper()
    clock.advance(by: .seconds(9))  // t = 19
    #expect(clock.sleeperCount == 1)
    clock.advance(by: .seconds(1))  // t = 20
    #expect(try await stage == .idle)
  }

  @Test func totalLimitStopsAChattyStream() async throws {
    let clock = ManualClock()
    let watchdog = Watchdog(clock: clock, timeouts: timeouts)
    async let stage = watchdog.expiry()
    for _ in 0..<24 {
      try await clock.waitForSleeper()
      watchdog.feed()
      clock.advance(by: .seconds(5))
    }
    #expect(try await stage == .total)
  }
}
