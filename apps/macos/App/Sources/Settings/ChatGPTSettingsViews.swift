// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import SwiftUI

/// The ChatGPT account in the model settings, as a card row on the settings page and a form
/// row in the onboarding: the guidelines' offer and "Continue with ChatGPT" when signed
/// out, the browser wait, or the account with "Manage usage" and Sign Out.
struct ChatGPTAccountRow: View {
  let model: SettingsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      switch model.chatGPT {
      case .signedOut(let previousEmail):
        title(ChatGPTText.offerTitle)
        note(previousEmail == nil ? ChatGPTText.offerBody : ChatGPTText.reconnect)
        ContinueWithChatGPTButton { model.signInWithChatGPT() }
      case .signingIn:
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          note(ChatGPTText.signingIn)
          Spacer(minLength: 0)
          CardButton(title: ChatGPTText.cancel) { model.cancelChatGPTSignIn() }
        }
      case .signedIn(let email, let canUsePlan):
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          VStack(alignment: .leading, spacing: 3) {
            title(ChatGPTText.signedIn(email))
            if canUsePlan {
              HStack(spacing: 6) {
                note(ChatGPTText.usingPlan)
                Link(ChatGPTText.manageUsage, destination: ChatGPTEndpoints.manageUsage)
                  .font(WindowType.footnote.font)
              }
            }
          }
          Spacer(minLength: 0)
          CardButton(title: ChatGPTText.signOut) { model.signOutOfChatGPT() }
        }
        if !canUsePlan {
          note(ChatGPTText.notGranted)
          ContinueWithChatGPTButton { model.signInWithChatGPT() }
        }
      }
      if let failure = model.chatGPTNote {
        Label {
          Text(failure).fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(Color(Palette.warningOnTint))
        }
        .font(WindowType.footnote.font)
        .foregroundStyle(Color(Palette.textSecondary))
        .textSelection(.enabled)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func title(_ text: String) -> some View {
    Text(text)
      .font(WindowType.row.font)
      .foregroundStyle(Color(Palette.textPrimary))
  }

  private func note(_ text: String) -> some View {
    Text(text)
      .font(WindowType.footnote.font)
      .lineSpacing(WindowType.footnote.lineSpacing)
      .foregroundStyle(Color(Palette.textSecondary))
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// The guidelines' "Continue with ChatGPT" button, black with white text. OpenAI's approved
/// formats also carry its logo, whose asset is not under a licence Dict can ship.
struct ContinueWithChatGPTButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(ChatGPTText.continueButton)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(Color.black, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
        .fixedSize()
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .focusRing(Capsule())
  }
}

/// The models the signed-in account lists, as a pop-up menu; the plan takes no typed name.
struct ChatGPTModelPicker: View {
  let model: SettingsModel

  var body: some View {
    if case .loaded(let names) = model.modelList, !names.isEmpty {
      Picker(
        ModelText.model,
        selection: Binding(
          get: { model.preferences.model.model }, set: { model.chooseModel($0) })
      ) {
        if !names.contains(model.preferences.model.model) {
          Text(model.preferences.model.model).tag(model.preferences.model.model)
        }
        ForEach(names, id: \.self) { Text($0).tag($0) }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .fixedSize()
    } else if model.modelList == .loading {
      ProgressView().controlSize(.small)
    } else {
      Button(ModelText.listModels) { model.listModels() }
        .disabled(!model.canListModels)
    }
  }
}

extension View {
  /// The guidelines' one-time notice after the first sign-in with plan usage.
  func chatGPTPlanWelcome(_ model: SettingsModel) -> some View {
    alert(
      ChatGPTText.welcomeTitle,
      isPresented: Binding(
        get: { model.showsPlanWelcome }, set: { if !$0 { model.dismissPlanWelcome() } })
    ) {
      Button(ChatGPTText.welcomeButton) { model.dismissPlanWelcome() }
    } message: {
      Text(ChatGPTText.welcomeBody)
    }
  }
}
