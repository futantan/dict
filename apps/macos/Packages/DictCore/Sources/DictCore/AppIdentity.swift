// SPDX-License-Identifier: GPL-3.0-or-later

/// Who the running app is: name, bundle identifier and version, as declared in its Info.plist.
public struct AppIdentity: Equatable, Sendable {
  public let name: String
  public let bundleIdentifier: String
  public let version: String
  public let build: String

  public init(name: String, bundleIdentifier: String, version: String, build: String) {
    self.name = name
    self.bundleIdentifier = bundleIdentifier
    self.version = version
    self.build = build
  }

  /// Reads the identity from a bundle's info dictionary.
  /// Returns nil when any required key is missing or empty.
  public init?(infoDictionary info: [String: Any]) {
    func value(_ key: String) -> String? {
      guard let string = info[key] as? String, !string.isEmpty else { return nil }
      return string
    }
    guard
      let name = value("CFBundleDisplayName") ?? value("CFBundleName"),
      let bundleIdentifier = value("CFBundleIdentifier"),
      let version = value("CFBundleShortVersionString"),
      let build = value("CFBundleVersion")
    else { return nil }
    self.init(name: name, bundleIdentifier: bundleIdentifier, version: version, build: build)
  }

  /// Human-readable version, e.g. "1.2.0 (42)".
  public var versionDescription: String { "\(version) (\(build))" }
}
