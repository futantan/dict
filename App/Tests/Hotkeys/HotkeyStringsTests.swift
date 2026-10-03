// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictApp

struct HotkeyStringsTests {
  private func chinese(_ key: String) throws -> String {
    let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    return bundle.localizedString(forKey: key, value: "<missing>", table: "Hotkeys")
  }

  @Test func rolesHaveChineseNames() throws {
    #expect(try chinese("Read") == "读")
    #expect(try chinese("Write") == "写")
  }

  @Test func layoutMessageReordersItsArgumentsInChinese() throws {
    let template = try chinese("This types “%@” with the %@ layout.")
    #expect(String(format: template, "å", "ABC") == "这个组合在「ABC」布局下会输入“å”。")
  }

  @Test func everyProblemHasAMessage() {
    let problems: [HotkeyProblem] = [
      .needsModifier, .appShortcut, .reserved, .usedBy(.read), .usedBy(.write),
      .typesCharacter("å", layoutName: "ABC"), .deadKey(layoutName: "ABC"),
      .registrationFailed(-9878), .registrationFailed(-50),
    ]
    #expect(Set(problems.map(\.message)).count == problems.count)
  }
}
