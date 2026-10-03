// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import Translation

/// The first-run window's content: one step at a time, with Back and Continue.
struct OnboardingView: View {
  let model: OnboardingModel
  let appName: String

  static let width: CGFloat = 560

  var body: some View {
    VStack(spacing: 0) {
      Group {
        switch model.step {
        case .accessibility: AccessibilityStep(model: model, appName: appName)
        case .shortcuts: HotkeyStepView(center: model.hotkeys)
        case .translation: TranslationStep(model: model)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)

      Divider()
      HStack(spacing: 12) {
        Text(
          String(
            localized: "Step \(model.step.rawValue + 1) of \(OnboardingStep.allCases.count)",
            comment: "Onboarding progress; the arguments are the step number and the step count")
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        Spacer()
        if model.step != .accessibility {
          Button(String(localized: "Back", comment: "Onboarding button")) { model.goBack() }
        }
        Button(
          model.step == .translation
            ? String(localized: "Done", comment: "Onboarding button that finishes it")
            : String(localized: "Continue", comment: "Onboarding button")
        ) { model.goForward() }
        .keyboardShortcut(.defaultAction)
        .disabled(!model.canContinue)
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 16)
    }
    .frame(width: Self.width)
    .fixedSize(horizontal: false, vertical: true)
    .translationTask(model.preparation, action: OnboardingModel.prepare)
  }
}

/// A step's title and explanation, styled like `HotkeyStepView`.
private struct StepHeader: View {
  let title: String
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.title2.bold())
      Text(message)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// A line with a status symbol, for granted permissions and ready languages.
private struct StatusLine: View {
  let text: String
  let symbol: String
  let tint: Color

  var body: some View {
    Label {
      Text(text).fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: symbol).foregroundStyle(tint)
    }
  }
}

private struct AccessibilityStep: View {
  let model: OnboardingModel
  let appName: String

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      StepHeader(
        title: String(
          localized: "Allow \(appName) to read selected text",
          comment: "Title of the onboarding accessibility step; the argument is the app name"),
        message: String(
          localized: """
            \(appName) reads the text you select through Accessibility. Turn on \(appName) in \
            System Settings → Privacy & Security → Accessibility; this window moves on by itself.
            """,
          comment: "Onboarding accessibility explanation; both arguments are the app name"))
      if model.permissions.accessibility {
        StatusLine(
          text: String(
            localized: "Accessibility is on.", comment: "Onboarding: the permission is granted"),
          symbol: "checkmark.circle.fill", tint: .green)
      } else {
        Button(
          String(
            localized: "Open System Settings",
            comment: "Onboarding button that opens the Accessibility settings")
        ) { model.openAccessibilitySettings() }
        .controlSize(.large)
      }
    }
    .padding(24)
  }
}

private struct TranslationStep: View {
  let model: OnboardingModel

  /// "Chinese, Simplified" rather than "Chinese": Chinese is named with its script.
  private func name(_ language: Locale.Language) -> String {
    let script = language.languageCode == .chinese ? language.script?.identifier : nil
    let identifier = [language.languageCode?.identifier, script].compactMap { $0 }
      .joined(separator: "-")
    return Locale.current.localizedString(forIdentifier: identifier) ?? identifier
  }

  var body: some View {
    let learning = name(model.pair.learning)
    let mine = name(model.pair.mine)
    VStack(alignment: .leading, spacing: 20) {
      StepHeader(
        title: String(
          localized: "Download translation languages",
          comment: "Title of the onboarding step that downloads Apple Translation languages"),
        message: String(
          localized: """
            Without a model, Dict translates on this Mac with Apple Translation. It needs \
            \(learning) and \(mine) downloaded once.
            """,
          comment: "Onboarding translation explanation; the arguments are two language names"))
      status(learning: learning, mine: mine)
      Divider()
      HStack(alignment: .firstTextBaseline) {
        Text(
          String(
            localized:
              "For streaming translations from OpenAI or another provider, add an API key in Settings.",
            comment: "Onboarding note about setting up a model")
        )
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 12)
        Button(String(localized: "Open Settings…", comment: "Onboarding button")) {
          model.openSettings()
        }
      }
    }
    .padding(24)
  }

  @ViewBuilder
  private func status(learning: String, mine: String) -> some View {
    switch model.languages {
    case .checking, .downloading:
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text(
          model.languages == .checking
            ? String(localized: "Checking…", comment: "Onboarding: checking the languages")
            : String(
              localized: "Waiting for the download…",
              comment: "Onboarding: the system is downloading the languages")
        )
        .foregroundStyle(.secondary)
      }
    case .installed:
      StatusLine(
        text: String(
          localized: "\(learning) and \(mine) are ready.",
          comment: "Onboarding: both languages are downloaded; the arguments are language names"),
        symbol: "checkmark.circle.fill", tint: .green)
    case .needsDownload:
      Button(
        String(
          localized: "Download Languages…",
          comment: "Onboarding button that asks macOS to download the translation languages")
      ) { model.downloadLanguages() }
      .controlSize(.large)
    case .unsupported:
      StatusLine(
        text: String(
          localized:
            "Apple Translation doesn’t support \(learning) and \(mine). Set up a model in Settings instead.",
          comment: "Onboarding: the pair is not supported; the arguments are language names"),
        symbol: "exclamationmark.triangle.fill", tint: .orange)
    }
  }
}
