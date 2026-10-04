// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

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
        case .model: ModelStep(model: model, appName: appName)
        case .tryIt: TryItStep(model: model)
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
        Button(forwardTitle) { model.goForward() }
          .keyboardShortcut(.defaultAction)
          .disabled(!model.canContinue)
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 16)
    }
    .frame(width: Self.width)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var forwardTitle: String {
    if model.isSkipping {
      return String(localized: "Not Now", comment: "Onboarding button that skips the model step")
    }
    return model.step == .tryIt
      ? String(localized: "Done", comment: "Onboarding button that finishes it")
      : String(localized: "Continue", comment: "Onboarding button")
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
        Label {
          Text(
            String(
              localized: "Accessibility is on.", comment: "Onboarding: the permission is granted"))
        } icon: {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
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

/// The provider, model and key, with the Settings window's own sections and "Test" button.
private struct ModelStep: View {
  let model: OnboardingModel
  let appName: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      StepHeader(
        title: String(
          localized: "Add your API key",
          comment: "Title of the onboarding step that sets up a model"
        ),
        message: String(
          localized: """
            \(appName) translates with a model you choose, using your own API key. Paste the key \
            and press Test. You can also do this later in Settings.
            """,
          comment: "Onboarding model explanation; the argument is the app name")
      )
      .padding([.horizontal, .top], 24)

      Form {
        ModelSections(model: model.settings)
      }
      .formStyle(.grouped)
      .scrollDisabled(true)
      // The grouped form insets its sections by 20 pt; 4 more line them up with the title.
      .padding(.horizontal, 4)
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// A sample translated in the real result panel, before the window closes.
private struct TryItStep: View {
  let model: OnboardingModel

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      StepHeader(
        title: String(localized: "Try it", comment: "Title of the onboarding step with a sample"),
        message: message)

      VStack(alignment: .leading, spacing: 12) {
        Text(OnboardingModel.sample)
          .font(.system(size: 14))
          .lineSpacing(3)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        HStack {
          Spacer()
          Button(
            String(
              localized: "Translate Sample",
              comment: "Onboarding button that translates the sample in the result panel")
          ) { model.translateSample() }
        }
      }
      .padding(14)
      .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
      .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) {
        model.sampleFrame = $0
      }
    }
    .padding(24)
  }

  private var message: String {
    guard let combo = model.hotkeys.combos[.read] else {
      return String(
        localized: "See a translation in the panel before you start.",
        comment: "Onboarding sample explanation when no Read shortcut is set")
    }
    return String(
      localized:
        "Select text in any app and press \(model.hotkeys.displayString(combo)). Or translate this sample now:",
      comment: "Onboarding sample explanation; the argument is the Read shortcut, such as ⌃⌥D")
  }
}
