// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import Foundation
import SwiftUI
import Testing

@testable import DictApp

private let renderDirectory = ProcessInfo.processInfo.environment["DICT_SETTINGS_RENDER_DIR"]

/// Renders the settings page's cards in sample states offscreen, at a fixed width: the
/// languages and shortcuts cards and every state of the model section. The whole page is
/// rendered by `MainWindowGalleryTests`.
///
/// `TEST_RUNNER_DICT_SETTINGS_RENDER_DIR=<dir> xcodebuild test … -only-testing:
/// DictAppTests/SettingsGalleryTests` writes one PNG per state and appearance into `<dir>`;
/// add `-testLanguage zh-Hans` for the Chinese UI. Nothing is shown on screen.
@MainActor
struct SettingsGalleryTests {
  static let width: CGFloat = 520

  /// Every sample has a sensible height at the fixed width, without a layout loop.
  @Test func panesFitTheirContent() {
    for (name, view) in Self.samples() {
      let size = Self.host(view, appearance: .aqua).fittingSize
      #expect(size.width == Self.width, "\(name)")
      #expect(size.height > 80 && size.height < 900, "\(name)")
    }
  }

  @Test(.enabled(if: renderDirectory != nil))
  func renderGallery() throws {
    let directory = URL(fileURLWithPath: try #require(renderDirectory))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let language = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? "zh" : "en"
    for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
      for (name, view) in Self.samples() {
        let png = try #require(Self.render(view, appearance: appearance))
        try png.write(to: directory.appendingPathComponent("\(language)-\(scheme)-\(name).png"))
      }
    }
  }

  // MARK: - Samples

  private static func samples() -> [(String, AnyView)] {
    func model(
      _ preferences: Preferences, key: String? = nil, connection: ConnectionStatus = .idle,
      list: ModelListStatus = .idle
    ) -> SettingsModel {
      let defaults = UserDefaults.scratch("SettingsGalleryTests")
      PreferencesStore(defaults: defaults).save(preferences)
      var secrets: [String: String] = [:]
      if let key, let id = preferences.model.providerID { secrets[id] = key }
      let model = SettingsModel(defaults: defaults, secrets: InMemorySecretStore(secrets))
      model.showConnection(connection)
      model.showModelList(list)
      return model
    }
    func chatGPT(_ model: SettingsModel, _ status: ChatGPTStatus, note: String? = nil)
      -> SettingsModel
    {
      model.showChatGPT(status, note: note)
      return model
    }
    func provider(_ id: String, model: String = "", baseURL: String = "") -> Preferences {
      Preferences(model: ModelPreferences(providerID: id, model: model, baseURL: baseURL))
    }
    let key = "sk-proj-sample-not-a-real-key"

    return [
      ("languages", card { LanguageRows(model: model(Preferences())) }),
      (
        "languages-japanese",
        card { LanguageRows(model: model(Preferences(myLanguage: "en", learningLanguage: "ja"))) }
      ),
      ("model-none", AnyView(ModelCard(model: model(Preferences())))),
      ("model-openai-nokey", AnyView(ModelCard(model: model(provider("openai"))))),
      (
        "model-openai-ok",
        AnyView(
          ModelCard(
            model: model(
              provider("openai"), key: key,
              connection: .checked(.translated(after: .milliseconds(840))))))
      ),
      (
        "model-openai-testing",
        AnyView(
          ModelCard(
            model: model(
              provider("openai"), key: key,
              connection: .checked(ConnectionReport(translation: .running)))))
      ),
      (
        "model-openai-unauthorized",
        AnyView(
          ModelCard(
            model: model(
              provider("openai"), key: key, connection: .checked(.failed(.model(.unauthorized))))))
      ),
      (
        "model-ollama",
        AnyView(
          ModelCard(
            model: model(
              provider("ollama", model: "qwen3:4b"),
              connection: .checked(.failed(.model(.network(code: -1004)))),
              list: .failed(.model(.network(code: -1004))))))
      ),
      (
        "model-ollama-listed",
        AnyView(
          ModelCard(
            model: model(
              provider("ollama", model: "qwen3:4b"),
              list: .loaded(["gemma3:1b", "llama3.2:3b", "qwen3:4b"]))))
      ),
      (
        "model-ollama-none-installed",
        AnyView(ModelCard(model: model(provider("ollama"), list: .loaded([]))))
      ),
      (
        "model-openai-notfound",
        AnyView(
          ModelCard(
            model: model(
              provider("openai", model: "gpt-9"), key: key,
              connection: .checked(.failed(.model(.modelNotFound))),
              list: .loaded(["gpt-5-nano", "gpt-6-luna", "gpt-6-sol"]))))
      ),
      (
        "model-openai-structured",
        AnyView(
          ModelCard(
            model: model(
              provider("openai"), key: key,
              connection: .checked(
                ConnectionReport(
                  translation: .passed, firstContent: .milliseconds(760),
                  structuredOutput: .running)))))
      ),
      (
        "model-ollama-thinking",
        AnyView(
          ModelCard(
            model: model(
              provider("ollama", model: "qwen3:4b"),
              connection: .checked(.translated(after: .milliseconds(4200), sawThinking: true)))))
      ),
      (
        "model-custom-json-failed",
        AnyView(
          ModelCard(
            model: model(
              provider("custom", model: "deepseek-chat", baseURL: "https://api.deepseek.com/v1"),
              key: key,
              connection: .checked(
                .translated(
                  after: .milliseconds(1100),
                  structuredOutput: .failed(.structuredOutput(.malformed)))))))
      ),
      (
        "model-custom-advanced",
        AnyView(
          ModelCard(
            model: model(
              provider("custom", model: "deepseek-chat", baseURL: "https://api.deepseek.com/v1"),
              key: key),
            showsAdvanced: true))
      ),
      (
        "model-openai-advanced",
        AnyView(ModelCard(model: model(provider("openai"), key: key), showsAdvanced: true))
      ),
      (
        "model-custom-insecure",
        AnyView(
          ModelCard(
            model: model(
              provider("custom", model: "deepseek-chat", baseURL: "http://api.deepseek.com/v1"))))
      ),
      (
        "model-custom-badrequest",
        AnyView(
          ModelCard(
            model: model(
              provider("custom", model: "deepseek-chat", baseURL: "https://api.deepseek.com/v1"),
              key: key,
              connection: .checked(
                .failed(
                  .model(
                    .badRequest(
                      message:
                        "Model Not Exist. Please check the model name and try again; see the documentation for the list of available models."
                    )))))))
      ),
      ("model-chatgpt-signedout", AnyView(ModelCard(model: model(provider("chatgpt"))))),
      (
        "model-chatgpt-signingin",
        AnyView(ModelCard(model: chatGPT(model(provider("chatgpt")), .signingIn)))
      ),
      (
        "model-chatgpt-failed",
        AnyView(
          ModelCard(
            model: chatGPT(
              model(provider("chatgpt")), .signedOut(previousEmail: "a@example.com"),
              note: ChatGPTText.signInFailure(ChatGPTSignInError.timedOut))))
      ),
      (
        "model-chatgpt-ok",
        AnyView(
          ModelCard(
            model: chatGPT(
              model(
                provider("chatgpt", model: "gpt-6.1-sol"),
                connection: .checked(.translated(after: .milliseconds(910))),
                list: .loaded(["gpt-6.1-sol", "gpt-6-astra"])),
              .signedIn(email: "a@example.com", canUsePlan: true))))
      ),
      (
        "model-chatgpt-limit",
        AnyView(
          ModelCard(
            model: chatGPT(
              model(
                provider("chatgpt", model: "gpt-6.1-sol"),
                connection: .checked(.failed(.model(.planLimitReached))),
                list: .loaded(["gpt-6.1-sol"])),
              .signedIn(email: "a@example.com", canUsePlan: true))))
      ),
      (
        "model-chatgpt-notgranted",
        AnyView(
          ModelCard(
            model: chatGPT(
              model(provider("chatgpt")), .signedIn(email: "a@example.com", canUsePlan: false))))
      ),
      (
        "shortcuts-empty",
        card { ShortcutRows(center: hotkeys(assigned: false)) }
      ),
      (
        "shortcuts",
        card { ShortcutRows(center: hotkeys(assigned: true)) }
      ),
    ]
  }

  /// The model section, as on the settings page.
  private struct ModelCard: View {
    let model: SettingsModel
    var showsAdvanced = false

    var body: some View {
      ModelSettingsSection(model: model, showsAdvanced: showsAdvanced).padding(20)
    }
  }

  /// Rows in a card, as on the settings page.
  private static func card(@ViewBuilder _ rows: () -> some View) -> AnyView {
    AnyView(WindowCard { rows() }.padding(20))
  }

  /// A center that loads sample combinations from a throwaway defaults suite and never
  /// registers them.
  private static func hotkeys(assigned: Bool) -> HotkeyCenter {
    let defaults = UserDefaults.scratch("SettingsGalleryTests.hotkeys")
    if assigned {
      HotkeyStore(defaults: defaults).save([
        .read: KeyCombo(keyCode: 2, modifiers: [.control, .option]),
        .write: KeyCombo(keyCode: 13, modifiers: [.control, .option]),
      ])
    }
    return HotkeyCenter(defaults: defaults)
  }

  // MARK: - Offscreen rendering

  private static func host(_ view: AnyView, appearance: NSAppearance.Name) -> NSHostingView<AnyView>
  {
    let host = NSHostingView(rootView: AnyView(view.frame(width: width)))
    host.appearance = NSAppearance(named: appearance)
    host.frame.size = host.fittingSize
    host.layoutSubtreeIfNeeded()
    return host
  }

  /// Draws the pane on the window background, at 2x.
  private static func render(_ view: AnyView, appearance: NSAppearance.Name) -> Data? {
    let content = host(view, appearance: appearance)
    let canvas = Backdrop(frame: CGRect(origin: .zero, size: content.frame.size))
    let window = NSWindow(
      contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: appearance)
    window.contentView = canvas
    canvas.addSubview(content)
    canvas.layoutSubtreeIfNeeded()

    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas.bounds.width * 2),
        pixelsHigh: Int(canvas.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
        bitsPerPixel: 0)
    else { return nil }
    bitmap.size = canvas.bounds.size
    canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
    return bitmap.representation(using: .png, properties: [:])
  }

  /// The settings page's background.
  private final class Backdrop: NSView {
    override func draw(_ dirtyRect: CGRect) {
      Palette.panelFill.setFill()
      bounds.fill()
    }
  }
}
