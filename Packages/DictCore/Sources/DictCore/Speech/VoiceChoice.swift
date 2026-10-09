// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How good a system voice sounds, lowest first. Mirrors the system's default (compact),
/// enhanced and premium tiers without depending on AVFoundation.
public enum VoiceQuality: Int, Sendable, Comparable, CaseIterable {
  case compact, enhanced, premium

  public static func < (lhs: VoiceQuality, rhs: VoiceQuality) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// An installed system voice as plain data, so the choice can be tested without the machine's
/// voices (architecture 9).
public struct VoiceInfo: Sendable, Equatable {
  /// The system identifier, for example `com.apple.voice.compact.en-US.Samantha`. Only valid
  /// for looking the voice up in the installed list: constructing a voice from it fails.
  public var identifier: String
  public var name: String
  /// BCP 47 as the system reports it, for example `en-US`.
  public var language: String
  public var quality: VoiceQuality
  /// The system marks joke voices such as Bubbles and Zarvox as novelty voices.
  public var isNovelty: Bool

  public init(
    identifier: String, name: String, language: String, quality: VoiceQuality,
    isNovelty: Bool = false
  ) {
    self.identifier = identifier
    self.name = name
    self.language = language
    self.quality = quality
    self.isNovelty = isNovelty
  }
}

/// What the user could download to sound better. At most one: getting a voice for the accent
/// is also how they get a better tier.
public enum VoiceHint: Sendable, Equatable {
  /// No voice speaks the language at all; nothing can be spoken.
  case noVoice
  /// No voice has the wanted accent; the choice is another region of the same language.
  case accentMissing
  /// The choice has the wanted accent but only the compact tier is installed.
  case higherQuality
}

public struct VoiceChoice: Sendable, Equatable {
  /// Nil when no installed voice speaks the language.
  public var voice: VoiceInfo?
  public var hint: VoiceHint?

  public init(voice: VoiceInfo?, hint: VoiceHint?) {
    self.voice = voice
    self.hint = hint
  }
}
