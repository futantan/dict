// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictApp

struct WritingStringsTests {
  private func chinese(_ key: String) throws -> String {
    let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    return bundle.localizedString(forKey: key, value: "<missing>", table: "Writing")
  }

  @Test func theActionsHaveChineseNames() throws {
    #expect(try chinese("Replace") == "替换")
    #expect(try chinese("Replaced · ⌘Z to undo") == "已替换 · ⌘Z 撤销")
  }

  @Test func theChangeCountIsPluralInEnglish() {
    #expect(WritingStrings.changes(1) == "1 change")
    #expect(WritingStrings.changes(3) == "3 changes")
  }

  @Test func everyToastHasItsOwnText() {
    let messages: [ToastMessage] = [
      .replaced, .notReplaced(result: "x"), .unconfirmed(clipboardHoldsResult: false),
      .unconfirmed(clipboardHoldsResult: true), .failed(result: "x"),
    ]
    #expect(Set(messages.map(\.text)).count == messages.count)
  }
}
