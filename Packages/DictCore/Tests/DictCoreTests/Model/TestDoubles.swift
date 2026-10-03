// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Synchronization

@testable import DictCore

/// A clock that only moves when the test advances it.
final class ManualClock: Clock, Sendable {
  struct Instant: InstantProtocol {
    var offset: Duration
    func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
    func duration(to other: Instant) -> Duration { other.offset - offset }
    static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
  }

  private struct Sleeper {
    let id: UUID
    let deadline: Instant
    let continuation: CheckedContinuation<Void, Error>
  }

  private struct State {
    var now = Instant(offset: .zero)
    var sleepers: [Sleeper] = []
  }

  private let state = Mutex(State())

  var now: Instant { state.withLock { $0.now } }
  var minimumResolution: Duration { .zero }
  var sleeperCount: Int { state.withLock { $0.sleepers.count } }

  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        let resumeNow = state.withLock { state in
          if deadline <= state.now || Task.isCancelled { return true }
          state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
          return false
        }
        if resumeNow { continuation.resume() }
      }
    } onCancel: {
      let sleeper = state.withLock { state in
        state.sleepers.firstIndex { $0.id == id }.map { state.sleepers.remove(at: $0) }
      }
      sleeper?.continuation.resume(throwing: CancellationError())
    }
    try Task.checkCancellation()
  }

  func advance(by duration: Duration) {
    let due = state.withLock { state in
      state.now = state.now.advanced(by: duration)
      let now = state.now
      let due = state.sleepers.filter { $0.deadline <= now }
      state.sleepers.removeAll { $0.deadline <= now }
      return due
    }
    for sleeper in due { sleeper.continuation.resume() }
  }

  /// Waits (in real time) until something sleeps on this clock.
  func waitForSleeper() async throws {
    try await eventually { self.sleeperCount > 0 }
  }
}

struct TimedOut: Error {}

/// Polls `condition` in real time for up to two seconds.
func eventually(_ condition: @Sendable () -> Bool) async throws {
  for _ in 0..<400 {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(5))
  }
  throw TimedOut()
}

/// A scripted HTTP reply.
struct StubReply: Sendable {
  var status = 200
  var headers = ["Content-Type": "text/event-stream"]
  var chunks: [String] = []
  /// False keeps the connection open after the chunks, like a stalled server.
  var finishes = true
}

/// Serves scripted replies to a `URLSession`. Each test registers its own host, so tests
/// running in parallel do not share state.
final class StubProtocol: URLProtocol, @unchecked Sendable {
  struct Host: Sendable {
    var reply: @Sendable (_ body: JSONValue) -> StubReply
    var bodies: [JSONValue] = []
    var headers: [[String: String]] = []
    var stopped = 0
  }

  private static let hosts = Mutex<[String: Host]>([:])

  /// Registers a fresh host and returns a session and base URL that reach it.
  static func register(
    _ reply: @escaping @Sendable (_ body: JSONValue) -> StubReply
  ) -> (session: URLSession, baseURL: URL, host: String) {
    let host = "\(UUID().uuidString.lowercased()).invalid"
    hosts.withLock { $0[host] = Host(reply: reply) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    let url = URL(string: "https://\(host)/v1") ?? URL(fileURLWithPath: "/")
    return (URLSession(configuration: configuration), url, host)
  }

  static func record(_ host: String) -> Host? { hosts.withLock { $0[host] } }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let host = request.url?.host() ?? ""
    let body =
      (try? JSONDecoder().decode(JSONValue.self, from: Self.bodyData(of: request))) ?? .null
    let reply = Self.hosts.withLock { hosts -> StubReply? in
      hosts[host]?.bodies.append(body)
      hosts[host]?.headers.append(request.allHTTPHeaderFields ?? [:])
      return hosts[host]?.reply(body)
    }
    guard let reply, let url = request.url,
      let response = HTTPURLResponse(
        url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    for chunk in reply.chunks { client?.urlProtocol(self, didLoad: Data(chunk.utf8)) }
    if reply.finishes { client?.urlProtocolDidFinishLoading(self) }
  }

  override func stopLoading() {
    let host = request.url?.host() ?? ""
    Self.hosts.withLock { $0[host]?.stopped += 1 }
  }

  private static func bodyData(of request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }
}
