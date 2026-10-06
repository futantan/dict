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
