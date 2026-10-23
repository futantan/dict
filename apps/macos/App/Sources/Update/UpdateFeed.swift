// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Decides whether the updater runs and which appcast it reads (Design/architecture.md 15.6).
/// nil from `resolve` means no updater is created, so no request is ever made.
enum UpdateFeed {
  /// Our Info.plist key for the appcast URL, from `DICT_UPDATE_FEED_URL` in the xcconfig.
  /// Not Sparkle's `SUFeedURL`: Sparkle gets its feed only from `Updater`, so it can never
  /// fall back to a placeholder.
  static let feedKey = "DictUpdateFeedURL"
  /// Sparkle's key for the EdDSA public key, from `DICT_UPDATE_PUBLIC_KEY`.
  static let publicKeyKey = "SUPublicEDKey"
  /// Debug only: a local appcast (`scripts/update-test.sh`), like `DICT_MOCK_MODEL`.
  static let feedVariable = "DICT_UPDATE_FEED"
  /// Debug only: `1` replaces Sparkle's windows with `HeadlessUserDriver`.
  static let headlessVariable = "DICT_UPDATE_HEADLESS"
  /// The account name in the committed placeholder feed URL.
  static let placeholderOwner = "OWNER"

  #if DEBUG
    static let isDebugBuild = true
  #else
    static let isDebugBuild = false
  #endif

  /// The appcast URL, or nil when updates are off.
  /// Release reads the Info.plist feed, which must be https and no longer the placeholder.
  /// Debug ignores it and reads only `DICT_UPDATE_FEED`, which must be `http://127.0.0.1`,
  /// so a development build can never update itself from the real feed.
  /// Both need a 32-byte EdDSA public key, without which Sparkle accepts no update.
  static func resolve(
    info: [String: Any], environment: [String: String], debug: Bool = isDebugBuild
  ) -> URL? {
    guard hasPublicKey(info) else { return nil }
    if debug {
      return environment[feedVariable].flatMap(url).flatMap(localFeed)
    }
    return (info[feedKey] as? String).flatMap(url).flatMap(releaseFeed)
  }

  static func isHeadless(_ environment: [String: String], debug: Bool = isDebugBuild) -> Bool {
    debug && environment[headlessVariable] == "1"
  }

  /// A quarantined app opened where it was downloaded runs from a randomized read-only
  /// path, which Sparkle cannot replace; the user has to move it to Applications first.
  static func isTranslocated(_ bundleURL: URL) -> Bool {
    bundleURL.pathComponents.contains("AppTranslocation")
  }

  private static func url(_ string: String) -> URL? {
    URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private static func localFeed(_ url: URL) -> URL? {
    url.scheme == "http" && url.host() == "127.0.0.1" ? url : nil
  }

  private static func releaseFeed(_ url: URL) -> URL? {
    guard url.scheme == "https", url.host()?.isEmpty == false,
      !url.pathComponents.contains(placeholderOwner)
    else { return nil }
    return url
  }

  private static func hasPublicKey(_ info: [String: Any]) -> Bool {
    guard let key = info[publicKeyKey] as? String else { return false }
    return Data(base64Encoded: key)?.count == 32
  }
}
