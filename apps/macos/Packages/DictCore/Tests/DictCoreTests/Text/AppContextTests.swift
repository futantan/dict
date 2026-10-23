// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import DictCore

/// The app a text is written in decides the register of a translate-out (architecture 5.3).
struct AppContextTests {
  @Test(arguments: [
    ("com.apple.mail", AppContext.mail),
    ("com.microsoft.Outlook", .mail),
    ("com.readdle.SparkDesktop", .mail),
    ("com.tencent.xinWeChat", .chat),
    ("com.tinyspeck.slackmacgap", .chat),
    ("com.hnc.Discord", .chat),
    ("ru.keepcoder.Telegram", .chat),
    ("com.apple.MobileSMS", .chat),
    ("com.apple.iWork.Pages", .document),
    ("com.microsoft.Word", .document),
    ("com.apple.Notes", .document),
    ("com.apple.TextEdit", .document),
    ("notion.id", .document),
    ("md.obsidian", .document),
    ("com.microsoft.VSCode", .code),
    ("com.apple.dt.Xcode", .code),
    ("com.todesktop.230313mxl6dzkn9", .code),
    ("com.apple.Terminal", .code),
    ("com.googlecode.iterm2", .code),
    ("com.mitchellh.ghostty", .code),
  ])
  func knownApps(bundleID: String, expected: AppContext) {
    #expect(appContext(bundleID: bundleID) == expected)
  }

  @Test func unknownAppsAndBrowsersAreOther() {
    #expect(appContext(bundleID: nil) == .other)
    #expect(appContext(bundleID: "") == .other)
    #expect(appContext(bundleID: "com.example.Unknown") == .other)
    // A browser hosts every kind of page, so the app alone says nothing.
    #expect(appContext(bundleID: "com.google.Chrome") == .other)
    #expect(appContext(bundleID: "com.apple.Safari") == .other)
  }

  /// Bundle ids compare without case; some apps report them in another case.
  @Test func matchingIgnoresCase() {
    #expect(appContext(bundleID: "COM.APPLE.MAIL") == .mail)
    #expect(appContext(bundleID: "com.apple.textedit") == .document)
  }

  /// An app is in one context only.
  @Test func theTableHasNoDuplicates() {
    let keys = appContexts.keys.map { $0.lowercased() }
    #expect(Set(keys).count == keys.count)
  }
}
