// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import Foundation
import Testing

@testable import DictApp

/// Checks the built app bundle that hosts these tests.
struct AppBundleTests {
  /// Dict starts as an agent and `AppPresence` makes it a regular app with a Dock icon at
  /// launch when the setting is on, so the test host, which is the app, never shows a Dock
  /// icon or takes focus, and stays an agent while the tests run.
  @Test @MainActor func infoPlistStartsAsAnAgentAndTheDockIconIsASetting() throws {
    let info = try #require(Bundle.main.infoDictionary)

    #expect(AppIdentity(infoDictionary: info) != nil)
    #expect(info["LSUIElement"] as? Bool == true)
    #expect(NSApplication.shared.activationPolicy() == .accessory)
  }

  @Test(arguments: [
    ("About %@", "关于 %@"),
    ("Quit %@", "退出 %@"),
    ("Check for Updates…", "检查更新…"),
    ("Couldn’t read the selection", "无法读取选中的文字"),
    ("Welcome to %@", "欢迎使用 %@"),
    ("Step %lld of %lld", "第 %1$lld 步，共 %2$lld 步"),
  ])
  func shipsSimplifiedChineseStrings(key: String, expected: String) throws {
    let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))

    #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == expected)
  }
}

struct LaunchModeTests {
  @Test func theTestHostStartsNothing() {
    #expect(
      LaunchMode.detect(environment: ["XCTestConfigurationFilePath": "/x"], arguments: ["app"])
        == .unitTests)
  }

  @Test func e2eRunsWithoutTheSession() {
    #expect(
      LaunchMode.detect(environment: [:], arguments: ["app", "--e2e", "s.json"]) == .endToEnd)
  }

  @MainActor @Test func windowDemoOpensTheNamedState() {
    #expect(
      LaunchMode.detect(environment: [:], arguments: ["app", "-DictWindowDemo", "review"])
        == .windowDemo("review"))
    #expect(MainWindowDemo.State.allCases.map(\.rawValue).contains("settings-model"))
  }

  @Test(arguments: [
    (["app"], true),
    (["app", "--no-onboarding"], false),
  ])
  func normalLaunchShowsOnboardingUnlessAsked(arguments: [String], shows: Bool) {
    #expect(
      LaunchMode.detect(environment: [:], arguments: arguments)
        == .normal(showsOnboarding: shows))
  }
}
