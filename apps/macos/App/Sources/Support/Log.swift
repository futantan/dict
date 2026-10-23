// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import os

/// The app's loggers (architecture 12). The subsystem is the bundle identifier, so the
/// Debug and Release builds log separately.
/// Log stage timings, paths taken, error codes and bundle ids; never user text or keys.
enum Log {
  static let subsystem = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName

  static let capture = Logger(subsystem: subsystem, category: "capture")
  static let replace = Logger(subsystem: subsystem, category: "replace")
  static let model = Logger(subsystem: subsystem, category: "model")
  static let store = Logger(subsystem: subsystem, category: "store")
  static let ui = Logger(subsystem: subsystem, category: "ui")
  static let update = Logger(subsystem: subsystem, category: "update")
}
