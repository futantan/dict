// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
  import Foundation

  extension UserDefaults {
    /// A new, empty defaults suite in the temporary directory, for the galleries, demos and
    /// tests. A suite named by an absolute path is kept in that file; one named otherwise
    /// lands in ~/Library/Preferences and stays there, as removing its domain leaves the
    /// file behind.
    static func scratch(_ name: String) -> UserDefaults {
      let file = FileManager.default.temporaryDirectory.appending(
        path: "\(name)-\(UUID().uuidString)-defaults")
      return UserDefaults(suiteName: file.path()) ?? UserDefaults()
    }
  }
#endif
