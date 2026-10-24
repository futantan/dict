// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

struct ModelListTests {
  private static let key = "sk-list-0123456789"

  // MARK: - URL

  @Test(arguments: [
    ("https://api.openai.com/v1", "https://api.openai.com/v1/models"),
    ("https://api.example.org/v1/", "https://api.example.org/v1/models"),
    ("https://openrouter.ai/api/v1", "https://openrouter.ai/api/v1/models"),
  ])
  func openAIStyleListsUnderTheBaseURL(base: String, expected: String) throws {
    let url = try #require(URL(string: base))
    #expect(modelListURL(baseURL: url, style: .openAI).absoluteString == expected)
  }

  @Test(arguments: [
    ("http://localhost:11434/v1", "http://localhost:11434/api/tags"),
    ("http://localhost:11434/v1/", "http://localhost:11434/api/tags"),
    ("http://127.0.0.1:11434", "http://127.0.0.1:11434/api/tags"),
  ])
  func ollamaListsItsTagsAtTheServerRoot(base: String, expected: String) throws {
    let url = try #require(URL(string: base))
    #expect(modelListURL(baseURL: url, style: .ollama).absoluteString == expected)
  }

  @Test func presetsSayHowToList() throws {
    let styles = Dictionary(
      uniqueKeysWithValues: try ProviderPreset.all().map { ($0.id, $0.modelList) })
    #expect(
      styles == ["openai": .openAI, "chatgpt": .chatGPT, "ollama": .ollama, "custom": .openAI])
  }

  // MARK: - Decoding

  @Test func decodesAnOpenAIListSortedWithoutDuplicates() throws {
    let json = """
      {"object":"list","data":[
        {"id":"gpt-6-luna","object":"model","created":1,"owned_by":"system"},
        {"id":"deepseek-chat","object":"model"},
        {"id":"gpt-6-luna","object":"model"},
        {"object":"model"}
      ]}
      """
    #expect(
      try decodeModelList(Data(json.utf8), style: .openAI) == ["deepseek-chat", "gpt-6-luna"])
  }

  @Test func decodesOllamaTagsByName() throws {
    let json = """
      {"models":[
        {"name":"qwen3:4b","model":"qwen3:4b","size":2497293931,"details":{"family":"qwen3"}},
        {"name":"llama3.2:3b","model":"llama3.2:3b"},
        {"model":"gemma3:1b"}
      ]}
      """
    #expect(
      try decodeModelList(Data(json.utf8), style: .ollama)
        == ["gemma3:1b", "llama3.2:3b", "qwen3:4b"])
  }

  /// Only listed entries, in the server's order, duplicates once.
  @Test func decodesTheChatGPTPlansListedSlugs() throws {
    let json = """
      {"models":[
        {"slug":"gpt-6.1-sol","display_name":"GPT-6.1 Sol","visibility":"list"},
        {"slug":"internal-x","display_name":"X","visibility":"hide"},
        {"slug":"gpt-6-astra","display_name":"GPT-6 Astra","visibility":"list"},
        {"slug":"gpt-6.1-sol","display_name":"GPT-6.1 Sol","visibility":"list"},
        {"display_name":"No slug","visibility":"list"}
      ]}
      """
    #expect(
      try decodeModelList(Data(json.utf8), style: .chatGPT) == ["gpt-6.1-sol", "gpt-6-astra"])
    #expect(throws: ModelError.malformedResponse) {
      try decodeModelList(Data(#"{"data":[{"id":"x"}]}"#.utf8), style: .chatGPT)
    }
  }

  @Test func emptyListsAreEmpty() throws {
    #expect(try decodeModelList(Data(#"{"models":[]}"#.utf8), style: .ollama) == [])
    #expect(try decodeModelList(Data(#"{"data":[]}"#.utf8), style: .openAI) == [])
  }

  @Test(arguments: [
    (#"<html>Not an API</html>"#, ModelListStyle.openAI),
    (#"{"data":"nope"}"#, .openAI),
    (#"{"models":[{"name":"x"}]}"#, .openAI),
    (#"{"data":[{"id":"x"}]}"#, .ollama),
    (#"[]"#, .ollama),
  ])
  func otherShapesAreMalformed(json: String, style: ModelListStyle) {
    #expect(throws: ModelError.malformedResponse) {
      try decodeModelList(Data(json.utf8), style: style)
    }
  }

  // MARK: - Request

  private func endpoint(_ baseURL: URL, auth: AuthStyle = .bearer) -> ModelEndpoint {
    ModelEndpoint(
      providerID: "custom", baseURL: baseURL, model: "", auth: auth, extraHeaders: [:],
      thinking: .off, jsonMode: .schema, tokenLimitField: "max_tokens")
  }

  private static func reply(_ status: Int, _ body: String) -> StubReply {
    StubReply(status: status, headers: ["Content-Type": "application/json"], chunks: [body])
  }

  @Test func getsTheListWithTheKey() async throws {
    let stub = StubProtocol.register { _ in
      Self.reply(200, #"{"object":"list","data":[{"id":"b"},{"id":"a"}]}"#)
    }

    let models = try await listModels(
      endpoint(stub.baseURL), style: .openAI, apiKey: Self.key, session: stub.session)

    #expect(models == ["a", "b"])
    let record = try #require(StubProtocol.record(stub.host))
    #expect(record.methods == ["GET"])
    #expect(record.urls.map(\.path) == ["/v1/models"])
    #expect(record.headers.first?["Authorization"] == "Bearer \(Self.key)")
  }

  @Test func ollamaGetsTagsWithoutAKey() async throws {
    let stub = StubProtocol.register { _ in
      Self.reply(200, #"{"models":[{"name":"qwen3:4b"}]}"#)
    }

    let models = try await listModels(
      endpoint(stub.baseURL, auth: .none), style: .ollama, apiKey: nil, session: stub.session)

    #expect(models == ["qwen3:4b"])
    let record = try #require(StubProtocol.record(stub.host))
    #expect(record.urls.map(\.path) == ["/api/tags"])
    #expect(record.headers.first?["Authorization"] == nil)
  }

  @Test(arguments: [
    (401, ModelError.unauthorized), (403, .unauthorized), (429, .rateLimited(retryAfter: nil)),
    (503, .server(status: 503)),
  ])
  func httpErrorsMapLikeChatErrors(status: Int, expected: ModelError) async {
    let stub = StubProtocol.register { _ in
      Self.reply(status, #"{"error":{"message":"nope","type":"x"}}"#)
    }

    await #expect(throws: expected) {
      try await listModels(
        endpoint(stub.baseURL), style: .openAI, apiKey: Self.key, session: stub.session)
    }
  }

  /// A 404 here means the service has no list endpoint, not that the model is missing.
  @Test(arguments: [404, 405])
  func missingListEndpointIsUnsupported(status: Int) async {
    let stub = StubProtocol.register { _ in Self.reply(status, "Not Found") }

    await #expect(throws: ModelListError.unsupported) {
      try await listModels(
        endpoint(stub.baseURL), style: .openAI, apiKey: Self.key, session: stub.session)
    }
  }

  @Test func errorMessagesHideTheKey() async {
    let stub = StubProtocol.register { _ in
      Self.reply(400, #"{"error":{"message":"bad key \#(Self.key)"}}"#)
    }

    await #expect(throws: ModelError.badRequest(message: "bad key ••••")) {
      try await listModels(
        endpoint(stub.baseURL), style: .openAI, apiKey: Self.key, session: stub.session)
    }
  }

  @Test func missingKeyFailsWithoutARequest() async throws {
    let stub = StubProtocol.register { _ in Self.reply(200, #"{"data":[]}"#) }

    await #expect(throws: ModelError.missingKey) {
      try await listModels(
        endpoint(stub.baseURL), style: .openAI, apiKey: nil, session: stub.session)
    }
    #expect(StubProtocol.record(stub.host)?.urls.isEmpty == true)
  }

  @Test func unreachableHostIsANetworkError() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    let session = URLSession(configuration: configuration)
    let base = try #require(URL(string: "https://unregistered.invalid/v1"))

    await #expect(throws: ModelError.network(code: URLError.cannotFindHost.rawValue)) {
      try await listModels(endpoint(base), style: .openAI, apiKey: Self.key, session: session)
    }
  }
}
