// SPDX-License-Identifier: GPL-3.0-or-later
//
// The fixture's event log (Design/m1-tasks.md, end-to-end interface): one JSON object per
// line, `{"time": <seconds>, "control": "<id>", "event": "<name>", "detail": "…"}`.
// Tests count these events, for example "no copy events on an accessibility-readable control".

import Foundation

enum FixtureEvent: String {
  case copy, paste, axWrite, select
  /// Written once the fixture listens for commands and its web page has loaded.
  case ready
}

@MainActor
final class EventLog {
  static let shared = EventLog(path: EventLog.pathFromArguments())

  private let handle: FileHandle?

  init(path: String?) {
    guard let path else {
      handle = nil
      return
    }
    FileManager.default.createFile(atPath: path, contents: nil)
    handle = FileHandle(forWritingAtPath: path)
  }

  func record(_ event: FixtureEvent, control: String, detail: String = "") {
    let line = Self.line(
      time: Date().timeIntervalSince1970, control: control, event: event, detail: detail)
    handle?.write(Data((line + "\n").utf8))
  }

  /// Encodes one log line. Keys are sorted so the output is stable.
  nonisolated static func line(
    time: TimeInterval, control: String, event: FixtureEvent, detail: String
  ) -> String {
    let object: [String: Any] = [
      "time": time, "control": control, "event": event.rawValue, "detail": detail,
    ]
    let data =
      (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    return String(decoding: data, as: UTF8.self)
  }

  /// The value after `--log` on the command line, if any.
  nonisolated static func pathFromArguments(
    _ arguments: [String] = CommandLine.arguments
  ) -> String? {
    guard let index = arguments.firstIndex(of: "--log"), index + 1 < arguments.count else {
      return nil
    }
    return arguments[index + 1]
  }
}
