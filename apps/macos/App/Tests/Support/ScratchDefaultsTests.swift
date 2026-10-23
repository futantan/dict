// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictApp

struct ScratchDefaultsTests {
  /// A scratch suite keeps its settings in the temporary directory, so test runs leave no
  /// files in ~/Library/Preferences.
  @Test func aScratchSuiteStaysInTheTemporaryDirectory() throws {
    let preferences = FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/Preferences")
    func scratchFiles() throws -> Set<String> {
      Set(
        try FileManager.default.contentsOfDirectory(atPath: preferences.path())
          .filter { $0.hasPrefix("ScratchDefaultsTests") })
    }
    let before = try scratchFiles()
    let defaults = UserDefaults.scratch("ScratchDefaultsTests")
    defaults.set(true, forKey: "written")
    defaults.synchronize()
    #expect(defaults.bool(forKey: "written"))
    #expect(try scratchFiles() == before)
  }
}
