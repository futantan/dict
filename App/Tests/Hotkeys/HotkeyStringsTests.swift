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

  @Test func everyProblemHasAMessage() {
    let problems: [HotkeyProblem] = [
      .needsModifier, .appShortcut, .reserved, .usedBy(.read), .usedBy(.write),
      .registrationFailed(-9878), .registrationFailed(-50),
    ]
    #expect(Set(problems.map(\.message)).count == problems.count)
  }
}
