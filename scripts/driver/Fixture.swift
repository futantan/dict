// SPDX-License-Identifier: GPL-3.0-or-later
//
// Starts CaptureFixture with an event log, brings it to the front, sends it commands over
// the distributed-notification channel, and reads its log.

import AppKit

@MainActor
final class Fixture {
  static let commandName = Notification.Name("au.ibra.dict.fixture.command")

  let app: URL
  let log: URL
  private(set) var pid: pid_t = 0

  init(app: URL, log: URL) {
    self.app = app
    self.log = log
  }

  /// Launches a new instance and waits for its `ready` event (its web page has loaded).
  func launch() throws {
    try? FileManager.default.removeItem(at: log)
    let status = shell(["open", "-n", "-F", app.path, "--args", "--log", log.path]).status
    guard status == 0 else { throw DriverError("could not open \(app.path)") }
    guard
      let ready = poll(timeout: 20, { readFixtureLog(log).first { $0.event == "ready" } }),
      let pid = pid_t(ready.detail)
    else { throw DriverError("CaptureFixture did not report ready within 20 s") }
    self.pid = pid
    Cleanup.add { [pid] in terminate(pid) }
  }

  /// Brings the fixture to the front through Launch Services.
  func activate() {
    shell(["open", "-a", app.path])
    _ = poll(timeout: 3) {
      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid ? true : nil
    }
  }

  var isFrontmost: Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }

  /// Number of log entries so far; pass it to `entries(since:)` to see what came after.
  var mark: Int { readFixtureLog(log).count }

  func entries(since mark: Int) -> [FixtureLogEntry] { Array(readFixtureLog(log).dropFirst(mark)) }

  /// Sends a select command and waits for the fixture to log its outcome.
  /// Returns the fixture's detail: the selected text, or "error: …".
  func select(_ control: String, _ text: String, content: String? = nil) -> String? {
    let before = mark
    var userInfo: [String: String] = ["command": "select", "control": control, "text": text]
    userInfo["content"] = content
    DistributedNotificationCenter.default().postNotificationName(
      Self.commandName, object: nil, userInfo: userInfo, deliverImmediately: true)
    return poll(timeout: 3) {
      entries(since: before).first { $0.event == "select" && $0.control == control }?.detail
    }
  }
}
