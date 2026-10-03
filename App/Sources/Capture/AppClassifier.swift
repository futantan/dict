// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Bundle identifiers and framework names that decide an app's kind (architecture 3.3).
/// The rules are inferred; only Chrome and VS Code were measured.
enum AppKindRules {
  static let terminals: Set<String> = [
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "com.mitchellh.ghostty",
    "net.kovidgoyal.kitty",
    "com.github.wez.wezterm",
    "org.alacritty",
    "dev.warp.Warp-Stable",
  ]

  static let chromiumBrowsers: Set<String> = [
    "com.google.Chrome",
    "com.google.Chrome.beta",
    "com.google.Chrome.dev",
    "com.google.Chrome.canary",
    "org.chromium.Chromium",
    "com.microsoft.edgemac",
    "com.brave.Browser",
    "company.thebrowser.Browser",
    "com.vivaldi.Vivaldi",
    "com.operasoftware.Opera",
  ]

  static let electronFramework = "Electron Framework.framework"
  static let chromiumFrameworkSuffixes = [
    "Chromium Framework.framework", "Chrome Framework.framework",
  ]
}

/// Classifies an app from its pid, bundle identifier and the names in `Contents/Frameworks`.
func classifyApp(pid: pid_t, ownPID: pid_t, bundleID: String?, frameworks: [String]) -> AppKind {
  if pid == ownPID { return .ownApp }
  if let bundleID, AppKindRules.terminals.contains(bundleID) { return .terminal }
  if frameworks.contains(AppKindRules.electronFramework) { return .electron }
  if let bundleID, AppKindRules.chromiumBrowsers.contains(bundleID) { return .chromium }
  let isChromium = frameworks.contains { name in
    AppKindRules.chromiumFrameworkSuffixes.contains { name.hasSuffix($0) }
  }
  return isChromium ? .chromium : .native
}

/// The framework bundle names inside an app, or none when the bundle cannot be read.
func frameworkNames(inBundle url: URL?) -> [String] {
  guard let url else { return [] }
  let frameworks = url.appending(path: "Contents/Frameworks", directoryHint: .isDirectory)
  return (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
}

extension TargetApp {
  /// Instances are keyed by pid and launch date, so a reused pid is a new instance.
  struct InstanceKey: Hashable, Sendable {
    let pid: pid_t
    let launchDate: Date?
  }

  var instanceKey: InstanceKey { InstanceKey(pid: pid, launchDate: launchDate) }
}

/// Builds `TargetApp` values, reading each bundle's frameworks once per app instance.
@MainActor
final class TargetAppResolver {
  private var kinds: [TargetApp.InstanceKey: AppKind] = [:]
  private let ownPID = ProcessInfo.processInfo.processIdentifier

  func resolve(_ app: NSRunningApplication) -> TargetApp {
    let key = TargetApp.InstanceKey(pid: app.processIdentifier, launchDate: app.launchDate)
    let kind =
      kinds[key]
      ?? classifyApp(
        pid: app.processIdentifier, ownPID: ownPID, bundleID: app.bundleIdentifier,
        frameworks: frameworkNames(inBundle: app.bundleURL))
    kinds[key] = kind
    return TargetApp(
      pid: app.processIdentifier, bundleID: app.bundleIdentifier, launchDate: app.launchDate,
      kind: kind)
  }
}
