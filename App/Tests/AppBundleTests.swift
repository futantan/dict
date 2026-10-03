// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Testing

/// Checks the built app bundle that hosts these tests.
struct AppBundleTests {
  @Test func infoPlistDescribesAMenuBarApp() throws {
    let info = try #require(Bundle.main.infoDictionary)

    #expect(AppIdentity(infoDictionary: info) != nil)
    #expect(info["LSUIElement"] as? Bool == true)
  }

  @Test(arguments: [
    ("About %@", "关于 %@"),
    ("Quit %@", "退出 %@"),
  ])
  func shipsSimplifiedChineseStrings(key: String, expected: String) throws {
    let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))

    #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == expected)
  }
}
