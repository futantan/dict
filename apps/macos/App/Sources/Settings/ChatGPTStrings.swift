// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// The wording of the ChatGPT sign-in. The English of the offer, the button, the first-use
/// notice and the usage limit is OpenAI's, from https://developers.openai.com/siwc/ui-ux-guidelines.
enum ChatGPTText {
  static let continueButton = String(
    localized: "Continue with ChatGPT", table: "Settings",
    comment: "Button that starts Sign in with ChatGPT (OpenAI's wording)")
  static let offerTitle = String(
    localized: "Use your ChatGPT plan", table: "Settings",
    comment: "Heading of the ChatGPT sign-in offer (OpenAI's wording)")
  static let offerBody = String(
    localized:
      "Complete eligible AI requests in this app with usage included in your ChatGPT plan or credits balance.",
    table: "Settings", comment: "Body of the ChatGPT sign-in offer (OpenAI's wording)")
  static let account = String(
    localized: "Account", table: "Settings", comment: "Settings field label: the ChatGPT account")
  static let signingIn = String(
    localized: "Finish signing in in your browser.", table: "Settings",
    comment: "Shown while waiting for the browser to sign in with ChatGPT")
  static let cancel = String(
    localized: "Cancel", table: "Settings", comment: "Stops waiting for the ChatGPT sign-in")
  static let signOut = String(
    localized: "Sign Out", table: "Settings", comment: "Button that signs out of ChatGPT")
  static let usingPlan = String(
    localized: "Using ChatGPT plan", table: "Settings",
    comment: "Indicator that requests use the ChatGPT plan (OpenAI's wording)")
  static let manageUsage = String(
    localized: "Manage usage", table: "Settings",
    comment: "Link to the usage page of the ChatGPT settings (OpenAI's wording)")
  static let reconnect = String(
    localized: "Your ChatGPT sign-in ended. Continue with ChatGPT to sign in again.",
    table: "Settings", comment: "The ChatGPT sign-in was refused or signed out")
  static let notGranted = String(
    localized:
      "You didn’t allow Dict to use your ChatGPT plan. Continue with ChatGPT again and allow plan usage, or use an API key with OpenAI.",
    table: "Settings", comment: "Signed in with ChatGPT without granting plan usage")
  static let signOutUnconfirmed = String(
    localized:
      "Signed out on this Mac, but OpenAI didn’t confirm it. To disconnect Dict from your account, open your ChatGPT settings.",
    table: "Settings", comment: "Signing out of ChatGPT: the revocation was not confirmed")
  static let privacyNote = String(
    localized:
      "Text you look up or translate is sent to OpenAI and counts toward your ChatGPT plan. Dict asks OpenAI not to store it. Your sign-in is kept in the Keychain.",
    table: "Settings", comment: "Privacy note under the ChatGPT provider")

  static let welcomeTitle = String(
    localized: "You’re using your ChatGPT plan", table: "Settings",
    comment: "Title of the one-time notice after signing in with ChatGPT (OpenAI's wording)")
  static let welcomeBody = String(
    localized:
      "Eligible usage in this app uses your ChatGPT plan. Manage usage in your ChatGPT settings.",
    table: "Settings",
    comment: "Body of the one-time notice after signing in with ChatGPT (OpenAI's wording)")
  static let welcomeButton = String(
    localized: "Got it", table: "Settings",
    comment: "Dismisses the one-time ChatGPT notice (OpenAI's wording)")

  static func signedIn(_ email: String?) -> String {
    guard let email else {
      return String(
        localized: "Signed in with ChatGPT", table: "Settings",
        comment: "ChatGPT account row without an email")
    }
    return String(
      localized: "Signed in as \(email)", table: "Settings",
      comment: "ChatGPT account row. The argument is the account's email")
  }

  /// Why signing in failed.
  static func signInFailure(_ error: any Error) -> String {
    switch error {
    case ChatGPTSignInError.denied("access_denied"):
      String(
        localized: "Sign-in was cancelled.", table: "Settings",
        comment: "The user cancelled on ChatGPT's consent page")
    case ChatGPTSignInError.timedOut:
      String(
        localized: "The browser didn’t finish signing in. Try again.", table: "Settings",
        comment: "Signing in with ChatGPT timed out")
    case ModelError.network:
      String(
        localized: "Couldn’t reach ChatGPT. Check your internet connection.", table: "Settings",
        comment: "Signing in with ChatGPT failed to connect")
    default:
      String(
        localized: "Couldn’t sign in with ChatGPT (\(logLabel(error))). Try again.",
        table: "Settings",
        comment: "Signing in with ChatGPT failed. The argument is a short technical reason")
    }
  }

  /// A short reason with no token or account in it, for the log and the failure message.
  static func logLabel(_ error: any Error) -> String {
    switch error {
    case let error as ChatGPTSignInError:
      switch error {
      case .stateMismatch: "state mismatch"
      case .denied(let code): code
      case .missingCode: "no code"
      case .missingClientID: "no client id"
      case .tokenRejected(let code): code
      case .malformedTokenResponse: "malformed token response"
      case .invalidIDToken(let claim): "ID token \(claim)"
      case .timedOut: "timed out"
      }
    case let error as KeychainError: "Keychain \(error.status)"
    case let error as ModelError: "\(error)"
    default: "\(type(of: error))"
    }
  }
}
