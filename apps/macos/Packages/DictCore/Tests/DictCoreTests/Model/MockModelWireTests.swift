// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

/// `scripts/fake-model.py` on a port the system picks, stopped when the value goes away.
private final class FakeModel {
  let process = Process()
  let port: Int

  init() throws {
    let script = (0..<6).reduce(URL(fileURLWithPath: #filePath)) { url, _ in
      url.deletingLastPathComponent()
    }.appending(path: "scripts/fake-model.py")
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [script.path, "0"]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    // The first line is the port, printed once the server accepts connections; EOF means
    // the script died.
    var line = Data()
    while !line.contains(UInt8(ascii: "\n")) {
      let data = output.fileHandleForReading.availableData
      if data.isEmpty { break }
      line.append(data)
    }
    guard let text = String(data: line, encoding: .utf8),
      let port = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      process.terminate()
      throw CocoaError(.fileReadCorruptFile)
    }
    self.port = port
  }

  deinit { process.terminate() }
}

/// The real client against the mock over HTTP: the mock's stream is what the client reads,
/// and it accepts every field the client sends, so nothing is dropped and retried.
struct MockModelWireTests {
  private func model(_ fake: FakeModel, dropped: DroppedParameters) throws -> ChatCompletionsModel {
    let preset = try #require(try ProviderPreset.all().first { $0.id == ProviderPreset.customID })
    var endpoint = preset.endpoint(model: "mock")
    endpoint.baseURL = try #require(URL(string: "http://127.0.0.1:\(fake.port)/v1"))
    return ChatCompletionsModel(
      endpoint: endpoint, rules: preset.thinkingRules, apiKey: "mock",
      session: URLSession(configuration: .ephemeral), dropped: dropped)
  }

  @Test func translationStreamsTheFixtureReply() async throws {
    let fake = try FakeModel()
    let dropped = DroppedParameters()
    let model = try model(fake, dropped: dropped)
    let request = PromptBuilder.translation(
      "The quick brown fox jumps over the lazy dog.",
      into: Locale.Language(identifier: "zh-Hans"), nonce: "0a1b2c3d")
    var text = ""
    var finish: FinishReason?
    var usage: Usage?
    for try await event in model.stream(request) {
      switch event {
      case .text(let delta): text += delta
      case .finished(let reason, let tokens): (finish, usage) = (reason, tokens)
      case .thinking, .discardText: break
      }
    }
    #expect(text == "[mock] 敏捷的棕色狐狸跳过了那只懒狗。")
    #expect(finish == .complete)
    #expect(usage != nil)
    #expect(dropped.names(for: model.endpoint).isEmpty)
  }

  /// The card streams in many deltas; the scanner has the definition while the arrays are
  /// still to come, and the whole answer decodes to the fixture card.
  @Test func cardStreamsItsDefinitionBeforeTheArrays() async throws {
    let fake = try FakeModel()
    let model = try model(fake, dropped: DroppedParameters())
    let request = PromptBuilder.card(
      term: "ran", context: "She ran a small bakery for ten years.", pair: LanguagePair(),
      accent: .american, nonce: "0a1b2c3d")
    var text = ""
    var scanner = TopLevelFieldScanner()
    var deltas = 0
    var textWhenDefinitionArrived: String?
    var finish: FinishReason?
    for try await event in model.stream(request) {
      switch event {
      case .text(let delta):
        text += delta
        deltas += 1
        scanner.feed(delta)
        if textWhenDefinitionArrived == nil, scanner.values["definition"] != nil {
          textWhenDefinitionArrived = text
        }
      case .finished(let reason, _): finish = reason
      case .thinking, .discardText: break
      }
    }
    #expect(finish == .complete)
    #expect(deltas > 4)
    #expect(scanner.values["definition"] == "[mock] 经营；管理")
    let early = try #require(textWhenDefinitionArrived)
    #expect(!early.contains("examples"))
    let card = try decodeCard(text)
    #expect(card.lemma == "run")
    #expect(card.definition == "[mock] 经营；管理")
    #expect(card.examples.count == 2)
  }

  @Test func proofreadingAppliesTheFixtureEdits() async throws {
    let fake = try FakeModel()
    let dropped = DroppedParameters()
    let proofreader = Proofreader(model: try model(fake, dropped: dropped))
    let applied = try await proofreader.proofread(
      "Their going to the park tomorow, I think it will be fun.")
    #expect(applied.text == "They're going to the park tomorrow. I think it will be fun.")
    #expect(applied.changeCount == 2)
  }
}

/// Stops at the first redirect, as the browser hands it to the loopback listener.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
  ) async -> URLRequest? { nil }
}

/// The ChatGPT plan against the mock with the real client code: authorize, callback,
/// exchange, the model list, a streamed translation and a strict-schema answer.
struct MockChatGPTWireTests {
  @Test func signInThenTranslateAndProofread() async throws {
    let fake = try FakeModel()
    let endpoints = ChatGPTEndpoints.mock(
      baseURL: try #require(URL(string: "http://127.0.0.1:\(fake.port)/v1")))
    let session = URLSession(configuration: .ephemeral)
    let attempt = AuthorizationAttempt.make(port: 1455)
    let url = attempt.url(endpoints, registration: .make(), appName: "Dict")

    let (_, response) = try await session.data(from: url, delegate: NoRedirects())
    let http = try #require(response as? HTTPURLResponse)
    #expect(http.statusCode == 302)
    let location = try #require(http.value(forHTTPHeaderField: "Location").flatMap(URL.init))
    let code = try attempt.callback(location)
    let clientID = try #require(code.clientID)
    #expect(clientID == "oaiapp_mock")

    let credential = try await exchangeAuthorizationCode(
      code, clientID: clientID, attempt: attempt, endpoints: endpoints, session: session)
    #expect(credential.canUsePlan)
    #expect(credential.email == "mock@example.com")

    let tokens = ChatGPTSession(
      endpoints: endpoints, store: MemoryCredentialStore(), session: session)
    try await tokens.signedIn(credential)
    let names = try await listChatGPTModels(
      endpoints: endpoints, tokens: tokens, session: session)
    #expect(names == ["mock"])

    let preset = try #require(try ProviderPreset.all().first { $0.id == "chatgpt" })
    let model = ResponsesModel(
      model: "mock", thinking: .off, rules: preset.thinkingRules, endpoints: endpoints,
      tokens: tokens, session: session)
    let request = PromptBuilder.translation(
      "The quick brown fox jumps over the lazy dog.",
      into: Locale.Language(identifier: "zh-Hans"), nonce: "0a1b2c3d")
    var text = ""
    var finish: FinishReason?
    for try await event in model.stream(request) {
      switch event {
      case .text(let delta): text += delta
      case .finished(let reason, _): finish = reason
      case .thinking, .discardText: break
      }
    }
    #expect(text == "[mock] 敏捷的棕色狐狸跳过了那只懒狗。")
    #expect(finish == .complete)

    let applied = try await Proofreader(model: model).proofread(
      "Their going to the park tomorow, I think it will be fun.")
    #expect(applied.changeCount == 2)
    #expect(await tokens.signOut())
  }
}
