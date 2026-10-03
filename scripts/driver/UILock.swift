// SPDX-License-Identifier: GPL-3.0-or-later
//
// The machine-wide lock for runs that take focus, post keys or use the clipboard. Other
// agents and scripts on this machine use the same directory as a mutex:
//   until mkdir /private/tmp/dict-ui.lock 2>/dev/null; do sleep 2; done; …; rmdir …
// A lock left unchanged for more than 10 minutes is treated as stale and removed.

import Foundation

@MainActor
enum UILock {
  static let path = "/private/tmp/dict-ui.lock"
  static let staleAfter: TimeInterval = 600

  /// Runs `body` while holding the lock, releasing it on every exit path.
  static func with<T>(_ reason: String, _ body: () throws -> T) rethrows -> T {
    acquire(reason)
    let cleanup = Cleanup.add { release() }
    defer { Cleanup.run(cleanup) }
    return try body()
  }

  private static func acquire(_ reason: String) {
    var announced = false
    while mkdir(path, 0o755) != 0 {
      if let modified = try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]
        as? Date, Date().timeIntervalSince(modified) > staleAfter
      {
        say("lock: removing stale \(path) (unchanged for over 10 minutes)")
        rmdir(path)
        continue
      }
      if !announced {
        say("lock: waiting for \(path)")
        announced = true
      }
      pause(2)
    }
    say("lock: acquired for \(reason)")
  }

  private static func release() {
    rmdir(path)
    say("lock: released")
  }
}
