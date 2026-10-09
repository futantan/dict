// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// The wording of pronunciation: the speaker buttons and the voice download hint (table
/// `Speech`).
enum SpeechStrings {
  static let speak = String(
    localized: "Pronounce", table: "Speech", comment: "Speaker button: say the text")

  static let speakSlowly = String(
    localized: "Pronounce Slowly", table: "Speech",
    comment: "Speaker button, pressed again: say the text slowly")

  static let noVoice = String(
    localized: "No voice is installed for this language.", table: "Speech",
    comment: "Shown when nothing can be spoken because no system voice speaks the language")

  /// What the user could download, or nil when the voice is already good.
  static func hint(_ hint: VoiceHint?) -> String? {
    switch hint {
    case nil:
      nil
    case .noVoice:
      String(
        localized: "No voice is installed for this language. Download one in System Settings.",
        table: "Speech", comment: "Voice hint when no system voice speaks the language")
    case .accentMissing:
      String(
        localized:
          "No voice with this accent is installed, so another accent is used. Download one in System Settings.",
        table: "Speech", comment: "Voice hint when no system voice has the chosen accent")
    case .higherQuality:
      String(
        localized:
          "For a more natural voice, download an Enhanced or Premium voice in System Settings.",
        table: "Speech", comment: "Voice hint when only the basic voice is installed")
    }
  }

  /// Opens System Settings → Accessibility → Spoken Content → System Voice → Manage Voices.
  static let manageVoices = String(
    localized: "Manage Voices…", table: "Speech",
    comment: "Button beside the voice hint that opens the system's voice downloads")
}
