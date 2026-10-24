// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Testing

@testable import DictApp

/// `scripts/fake-model.py` on a port the system picks, stopped when the value goes away.
private final class FakeModelServer {
  let process = Process()
  let port: Int

  init() throws {
    let script = (0..<4).reduce(URL(fileURLWithPath: #filePath)) { url, _ in
      url.deletingLastPathComponent()
    }.appending(path: "scripts/fake-model.py")
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [script.path, "0"]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
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

/// Stops at the authorization server's redirect, which the test then follows by hand.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
  ) async -> URLRequest? { nil }
}

/// Plays the browser: asks the authorization server, then takes its redirect to the app's
/// loopback listener.
private func browse(_ url: URL) async {
  let session = URLSession(configuration: .ephemeral)
  guard let (_, response) = try? await session.data(from: url, delegate: NoRedirects()),
    let location = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"),
    let callback = URL(string: location)
  else { return }
  _ = try? await session.data(from: callback)
}

/// The app's whole ChatGPT path against the mock, as `make run-mock` runs it: Settings signs
/// in through the real loopback listener and token exchange, lists the account's models and
/// runs the Test button's two requests on the Responses wire, then signs out. Only the
/// browser is played by the test.
@MainActor
struct ChatGPTMockSignInTests {
  @Test func signInListTestAndSignOut() async throws {
    let fake = try FakeModelServer()
    let base = try #require(URL(string: "http://127.0.0.1:\(fake.port)/v1"))
    let account = ChatGPTAccount(endpoints: .mock(baseURL: base), secrets: InMemorySecretStore())
    let model = SettingsModel(
      defaults: .scratch("ChatGPTMockSignInTests"), secrets: InMemorySecretStore(),
      chatGPT: account,
      signIn: { account in
        try await ChatGPTSignIn(account: account, openURL: browse, preferredPort: 0).run()
      })
    model.selectProvider(ProviderPreset.chatGPTID)
    model.signInWithChatGPT()
    for _ in 0..<1000 where model.chatGPT == .signingIn || model.modelList != .loaded(["mock"]) {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(model.chatGPT == .signedIn(email: "mock@example.com", canUsePlan: true))
    #expect(model.modelList == .loaded(["mock"]))
    #expect(model.preferences.model.model == "mock")
    #expect(try account.registrations.saved()?.clientID == "oaiapp_mock")

    model.testConnection()
    for _ in 0..<1000 where model.connection.isTesting {
      try await Task.sleep(for: .milliseconds(10))
    }
    guard case .checked(let report) = model.connection else {
      Issue.record("Expected a report, got \(model.connection)")
      return
    }
    #expect(report.translation == .passed)
    #expect(report.structuredOutput == .passed)

    model.signOutOfChatGPT()
    for _ in 0..<1000 where model.chatGPT.isSignedIn {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(model.chatGPT == .signedOut(previousEmail: "mock@example.com"))
    #expect(model.chatGPTNote == nil)
  }
}
