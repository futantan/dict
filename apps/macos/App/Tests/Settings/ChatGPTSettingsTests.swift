// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Synchronization
import Testing

@testable import DictApp

/// Nothing listens on port 9, so nothing here reaches OpenAI.
private let offline = ChatGPTEndpoints.mock(
  baseURL: URL(string: "http://127.0.0.1:9/v1") ?? URL(fileURLWithPath: "/"))

private func credential(canUsePlan: Bool = true) -> ChatGPTCredential {
  ChatGPTCredential(
    clientID: "oaiapp_1", subject: "user-1", email: "a@example.com", idToken: "id",
    accessToken: "access", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600),
    earliestRefreshAt: nil,
    scopes: canUsePlan ? Set(ChatGPTAuth.scopes) : ["openid", "email", "offline_access"])
}

/// Ends every request at once: nothing leaves the Mac.
private struct SilentModel: TextModel {
  func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, Error> {
    AsyncThrowingStream { $0.finish(throwing: ModelError.emptyResponse) }
  }
}

private final class Wires: Sendable {
  let built = Mutex<[ModelWire]>([])
}

@MainActor
struct ChatGPTSettingsTests {
  private let defaults = UserDefaults.scratch("ChatGPTSettingsTests")
  private let secrets = InMemorySecretStore()
  private let account: ChatGPTAccount
  private let wires = Wires()

  init() {
    account = ChatGPTAccount(endpoints: offline, secrets: secrets)
  }

  private func makeModel(
    signIn: @escaping SettingsModel.ChatGPTSignInRunner = { _ in credential() },
    models: [String] = ["gpt-6.1-sol", "gpt-6-luna"]
  ) -> SettingsModel {
    SettingsModel(
      defaults: defaults, secrets: secrets,
      makeModel: { [wires] configuration, _ in
        wires.built.withLock { $0.append(configuration.wire) }
        return SilentModel()
      },
      chatGPT: account,
      signIn: { account in
        let credential = try await signIn(account)
        try await account.session.signedIn(credential)
        return credential
      },
      listChatGPTModels: { _ in models })
  }

  private func settle(_ model: SettingsModel) async {
    for _ in 0..<400 where model.chatGPT == .signingIn || model.modelList == .loading {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  @Test func choosingChatGPTAsksToSignIn() {
    let model = makeModel()
    model.selectProvider(ProviderPreset.chatGPTID)
    #expect(model.isChatGPT)
    #expect(!model.acceptsKey)
    #expect(model.chatGPT == .signedOut(previousEmail: nil))
    #expect(model.setupIssue == .notSignedIn)
    #expect(!model.canTest)
  }

  @Test func signingInListsTheModelsAndPicksTheDefaultOnce() async {
    let model = makeModel()
    model.selectProvider(ProviderPreset.chatGPTID)
    model.signInWithChatGPT()
    await settle(model)

    #expect(model.chatGPT == .signedIn(email: "a@example.com", canUsePlan: true))
    #expect(model.modelList == .loaded(["gpt-6.1-sol", "gpt-6-luna"]))
    // OpenAI's default when the account lists it, not the first.
    #expect(model.preferences.model.model == "gpt-6-luna")
    #expect(model.setupIssue == nil)
    #expect(model.showsPlanWelcome)

    model.dismissPlanWelcome()
    #expect(!model.showsPlanWelcome)
    model.signInWithChatGPT()
    await settle(model)
    #expect(!model.showsPlanWelcome)
  }

  @Test func withoutTheDefaultTheFirstListedModelIsChosen() async {
    let model = makeModel(models: ["gpt-6.1-sol", "gpt-6-astra"])
    model.selectProvider(ProviderPreset.chatGPTID)
    model.signInWithChatGPT()
    await settle(model)
    #expect(model.preferences.model.model == "gpt-6.1-sol")
  }

  /// Launched already signed in, the menu gets the account's models without a click.
  @Test func aSavedSignInListsTheModelsOnLaunch() async throws {
    try await account.session.signedIn(credential())
    PreferencesStore(defaults: defaults).save(
      Preferences(model: ModelPreferences(providerID: "chatgpt", model: "gpt-6.1-sol")))
    let model = makeModel()
    await settle(model)
    #expect(model.modelList == .loaded(["gpt-6.1-sol", "gpt-6-luna"]))
    #expect(model.preferences.model.model == "gpt-6.1-sol")
  }

  @Test func theTestUsesTheResponsesWire() async {
    let model = makeModel()
    model.selectProvider(ProviderPreset.chatGPTID)
    model.signInWithChatGPT()
    await settle(model)
    model.testConnection()
    #expect(wires.built.withLock { $0 } == [.chatGPT])
  }

  @Test func aSignInWithoutPlanUsageSaysSo() async {
    let model = makeModel(signIn: { _ in credential(canUsePlan: false) })
    model.selectProvider(ProviderPreset.chatGPTID)
    model.signInWithChatGPT()
    await settle(model)
    #expect(model.chatGPT == .signedIn(email: "a@example.com", canUsePlan: false))
    #expect(model.modelList == .idle)
    #expect(!model.showsPlanWelcome)
  }

  @Test func aFailedSignInExplains() async {
    let model = makeModel(signIn: { _ in throw ChatGPTSignInError.denied("access_denied") })
    model.selectProvider(ProviderPreset.chatGPTID)
    model.signInWithChatGPT()
    await settle(model)
    #expect(model.chatGPT == .signedOut(previousEmail: nil))
    #expect(
      model.chatGPTNote == ChatGPTText.signInFailure(ChatGPTSignInError.denied("access_denied")))
  }

  @Test func signingOutForgetsTheAccount() async throws {
    try await account.session.signedIn(credential())
    try account.registrations.save(
      ChatGPTRegistration(hostID: "urn:uuid:h", clientID: "oaiapp_1", email: "a@example.com"))
    let model = makeModel()
    model.selectProvider(ProviderPreset.chatGPTID)
    #expect(model.chatGPT.isSignedIn)

    model.signOutOfChatGPT()
    for _ in 0..<400 where model.chatGPT.isSignedIn {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(model.chatGPT == .signedOut(previousEmail: "a@example.com"))
    // Nothing answers on port 9: the revocation is unconfirmed, and the note says so.
    #expect(model.chatGPTNote == ChatGPTText.signOutUnconfirmed)
    #expect(account.savedCredential == nil)
  }
}

struct ChatGPTModelSetupTests {
  private let presets = (try? ProviderPreset.all()) ?? []
  private let preferences = ModelPreferences(providerID: "chatgpt", model: "gpt-6.1-sol")

  @Test func withoutASignInThereIsNoModel() {
    let account = ChatGPTAccount(endpoints: offline, secrets: InMemorySecretStore())
    #expect(
      configuredModel(
        preferences, presets: presets, secrets: InMemorySecretStore(), chatGPT: account,
        environment: [:]) == nil)
  }

  @Test func aSignInMakesAResponsesModel() async throws {
    let account = ChatGPTAccount(endpoints: offline, secrets: InMemorySecretStore())
    try await account.session.signedIn(credential())
    let configured = try #require(
      configuredModel(
        preferences, presets: presets, secrets: InMemorySecretStore(), chatGPT: account,
        environment: [:]))
    #expect(configured.apiKey == nil)
    #expect(configured.configuration.wire == .chatGPT)
    let model = try #require(
      makeTextModel(configured.configuration, apiKey: nil, chatGPT: account) as? ResponsesModel)
    #expect(model.model == "gpt-6.1-sol")
    #expect(model.thinking == .off)
    #expect(model.endpoints == offline)
  }

  /// Under the mock, ChatGPT keeps its own wire (signed in to the mock), and the other
  /// providers still go to the mock's Chat Completions.
  @Test func theMockLeavesChatGPTOnItsWire() async throws {
    let account = ChatGPTAccount(endpoints: offline, secrets: InMemorySecretStore())
    try await account.session.signedIn(credential())
    let mock = ["DICT_MOCK_MODEL": "http://127.0.0.1:8767/v1"]
    let configured = try #require(
      configuredModel(
        preferences, presets: presets, secrets: InMemorySecretStore(), chatGPT: account,
        environment: mock))
    #expect(configured.configuration.wire == .chatGPT)
    let other = try #require(
      configuredModel(
        ModelPreferences(providerID: "openai"), presets: presets, secrets: InMemorySecretStore(),
        chatGPT: account, environment: mock))
    #expect(other.configuration.endpoint.providerID == ProviderPreset.customID)
  }
}
