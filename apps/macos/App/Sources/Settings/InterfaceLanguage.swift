// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The language of the app's own text: Simplified Chinese unless the user picked English in
/// Settings, whatever the system language (architecture 13).
///
/// The choice is stored under its own key. At launch, before any text is localized, it is
/// copied into the app's own `AppleLanguages`, which macOS reads to pick the bundle's
/// localization (above the system list, below a `-AppleLanguages` launch argument). So a new
/// choice shows after a relaunch, which Settings offers.
enum InterfaceLanguage: String, CaseIterable, Sendable {
  case simplifiedChinese = "zh-Hans"
  case english = "en"

  static let key = "InterfaceLanguage"
  static let fallback = InterfaceLanguage.simplifiedChinese

  /// The option's name in its own language, so either can be found whatever the UI shows.
  var name: String {
    switch self {
    case .simplifiedChinese: "简体中文"
    case .english: "English"
    }
  }

  /// The language of a bundle localization such as `Bundle.main.preferredLocalizations[0]`.
  init(localization: String) {
    self = localization.hasPrefix("zh") ? .simplifiedChinese : .english
  }

  /// The user's choice, or the default when there is none.
  static func chosen(in defaults: UserDefaults) -> InterfaceLanguage {
    defaults.string(forKey: key).flatMap(InterfaceLanguage.init(rawValue:)) ?? fallback
  }

  func choose(in defaults: UserDefaults) {
    defaults.set(rawValue, forKey: Self.key)
  }

  /// Run first thing in `main`: localizations are resolved once per process, on first use.
  static func applyAtLaunch(to defaults: UserDefaults) {
    defaults.set(appleLanguages(in: defaults), forKey: "AppleLanguages")
  }

  /// The app's own `AppleLanguages` for the choice in `defaults`.
  static func appleLanguages(in defaults: UserDefaults) -> [String] {
    [chosen(in: defaults).rawValue]
  }

  /// The localization this process runs in, fixed at launch.
  static var running: InterfaceLanguage {
    InterfaceLanguage(localization: Bundle.main.preferredLocalizations.first ?? "en")
  }

  /// Quits, then opens this same app again once this process has exited, so the two never
  /// run together. Touches no other instance, such as a second build of the app.
  @MainActor static func relaunch() {
    let waiter = Process()
    waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
    waiter.arguments = [
      "-c", #"while kill -0 "$0" 2>/dev/null; do sleep 0.1; done; exec /usr/bin/open -n "$1""#,
      String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path,
    ]
    do {
      try waiter.run()
      NSApp.terminate(nil)
    } catch {
      Log.ui.error("relaunch: \(String(describing: error), privacy: .public)")
    }
  }
}
