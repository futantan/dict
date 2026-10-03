// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import DictApp

struct AppClassifierTests {
  struct Case: Sendable, CustomTestStringConvertible {
    let pid: Int32
    let bundleID: String?
    let frameworks: [String]
    let expected: AppKind
    var testDescription: String { "\(bundleID ?? "nil") \(frameworks) → \(expected)" }
  }

  static let ownPID: Int32 = 100

  static let cases: [Case] = [
    Case(pid: 100, bundleID: "com.apple.TextEdit", frameworks: [], expected: .ownApp),
    Case(pid: 200, bundleID: "com.apple.TextEdit", frameworks: [], expected: .native),
    Case(
      pid: 200, bundleID: "com.apple.Safari", frameworks: ["Safari.framework"], expected: .native),
    Case(pid: 200, bundleID: nil, frameworks: [], expected: .native),
    Case(pid: 200, bundleID: "com.apple.Terminal", frameworks: [], expected: .terminal),
    Case(pid: 200, bundleID: "com.mitchellh.ghostty", frameworks: [], expected: .terminal),
    Case(pid: 200, bundleID: "com.googlecode.iterm2", frameworks: [], expected: .terminal),
    Case(pid: 200, bundleID: "net.kovidgoyal.kitty", frameworks: [], expected: .terminal),
    Case(pid: 200, bundleID: "com.github.wez.wezterm", frameworks: [], expected: .terminal),
    Case(pid: 200, bundleID: "org.alacritty", frameworks: [], expected: .terminal),
    Case(pid: 200, bundleID: "dev.warp.Warp-Stable", frameworks: [], expected: .terminal),
    Case(pid: 200, bundleID: "com.google.Chrome", frameworks: [], expected: .chromium),
    Case(pid: 200, bundleID: "com.microsoft.edgemac", frameworks: [], expected: .chromium),
    Case(
      pid: 200, bundleID: "com.example.browser",
      frameworks: ["Example Chromium Framework.framework"], expected: .chromium),
    Case(
      pid: 200, bundleID: "com.google.Chrome.canary",
      frameworks: ["Google Chrome Framework.framework"], expected: .chromium),
    Case(
      pid: 200, bundleID: "com.microsoft.VSCode",
      frameworks: ["Electron Framework.framework", "Squirrel.framework"], expected: .electron),
    // Electron bundles Chromium; the Electron framework wins.
    Case(
      pid: 200, bundleID: "com.example.app",
      frameworks: ["Electron Framework.framework", "Chromium Framework.framework"],
      expected: .electron),
    // Own pid wins over every list.
    Case(pid: 100, bundleID: "com.google.Chrome", frameworks: [], expected: .ownApp),
  ]

  @Test(arguments: cases) func classifies(_ c: Case) {
    let kind = classifyApp(
      pid: c.pid, ownPID: Self.ownPID, bundleID: c.bundleID, frameworks: c.frameworks)
    #expect(kind == c.expected)
  }
}
