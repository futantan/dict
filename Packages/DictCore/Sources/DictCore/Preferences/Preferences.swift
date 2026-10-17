// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// An English accent for speech (architecture 9). Explicit, not taken from the region.
public enum Accent: String, Codable, Sendable, CaseIterable {
  case american, british, australian, canadian, indian

  /// The region code of the accent, for example "US".
  public var region: String {
    switch self {
    case .american: "US"
    case .british: "GB"
    case .australian: "AU"
    case .canadian: "CA"
    case .indian: "IN"
    }
  }

  /// The language to pick voices from, for example en-GB.
  public var language: Locale.Language { Locale.Language(identifier: "en-\(region)") }
}

/// The user's settings other than shortcuts and secrets (architecture 13). The app stores
/// it in UserDefaults as one JSON value; missing or unknown fields decode to the defaults,
/// so older and newer versions read each other's data.
public struct Preferences: Codable, Sendable, Equatable {
  /// The languages offered for both sides of the pair, as BCP 47 identifiers.
  public static let languages = [
    "zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es", "it", "pt", "ru",
  ]

  /// The user's own language, a BCP 47 identifier.
  public var myLanguage: String
  /// The language the user is learning, a BCP 47 identifier.
  public var learningLanguage: String
  /// Used when the learning language is English.
  public var accent: Accent
  public var model: ModelPreferences
  /// Whether a replacement keeps the source's formatting (architecture 4.7). On by default.
  public var keepsFormatting: Bool
  /// The Dock icon and the menu bar icon (Design/main-app/README.md). At least one stays on,
  /// so they change through `setShowsDockIcon` and `setShowsMenuBarIcon`.
  public private(set) var showsDockIcon: Bool
  public private(set) var showsMenuBarIcon: Bool
  /// Whether closing the main window leaves Dict running with its shortcuts.
  public var keepsRunningAfterClose: Bool

  public init(
    myLanguage: String = "zh-Hans", learningLanguage: String = "en", accent: Accent = .american,
    model: ModelPreferences = ModelPreferences(), keepsFormatting: Bool = true,
    showsDockIcon: Bool = true, showsMenuBarIcon: Bool = true, keepsRunningAfterClose: Bool = true
  ) {
    self.myLanguage = myLanguage
    self.learningLanguage = learningLanguage
    self.accent = accent
    self.model = model
    self.keepsFormatting = keepsFormatting
    // Both off would leave no way back to the app.
    self.showsDockIcon = showsDockIcon || !showsMenuBarIcon
    self.showsMenuBarIcon = showsMenuBarIcon
    self.keepsRunningAfterClose = keepsRunningAfterClose
  }

  /// Hiding the Dock icon is refused while the menu bar icon is hidden.
  public mutating func setShowsDockIcon(_ shows: Bool) {
    guard shows || showsMenuBarIcon else { return }
    showsDockIcon = shows
  }

  /// Hiding the menu bar icon is refused while the Dock icon is hidden.
  public mutating func setShowsMenuBarIcon(_ shows: Bool) {
    guard shows || showsDockIcon else { return }
    showsMenuBarIcon = shows
  }

  public var languagePair: LanguagePair {
    LanguagePair(
      mine: Locale.Language(identifier: myLanguage),
      learning: Locale.Language(identifier: learningLanguage))
  }

  /// Sets my language; choosing the learning language swaps the two.
  public mutating func setMyLanguage(_ identifier: String) {
    if identifier == learningLanguage { learningLanguage = myLanguage }
    myLanguage = identifier
  }

  /// Sets the learning language; choosing my language swaps the two.
  public mutating func setLearningLanguage(_ identifier: String) {
    if identifier == myLanguage { myLanguage = learningLanguage }
    learningLanguage = identifier
  }

  private enum CodingKeys: String, CodingKey {
    case myLanguage, learningLanguage, accent, model, keepsFormatting, showsDockIcon,
      showsMenuBarIcon, keepsRunningAfterClose
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = Preferences()
    myLanguage =
      try container.decodeIfPresent(String.self, forKey: .myLanguage) ?? defaults.myLanguage
    learningLanguage =
      try container.decodeIfPresent(String.self, forKey: .learningLanguage)
      ?? defaults.learningLanguage
    accent = (try? container.decodeIfPresent(Accent.self, forKey: .accent)) ?? defaults.accent
    model = try container.decodeIfPresent(ModelPreferences.self, forKey: .model) ?? defaults.model
    keepsFormatting =
      (try? container.decodeIfPresent(Bool.self, forKey: .keepsFormatting))
      ?? defaults.keepsFormatting
    let flag = { (key: CodingKeys, fallback: Bool) in
      (try? container.decodeIfPresent(Bool.self, forKey: key)) ?? fallback
    }
    showsMenuBarIcon = flag(.showsMenuBarIcon, defaults.showsMenuBarIcon)
    showsDockIcon = flag(.showsDockIcon, defaults.showsDockIcon) || !showsMenuBarIcon
    keepsRunningAfterClose = flag(.keepsRunningAfterClose, defaults.keepsRunningAfterClose)
  }
}
