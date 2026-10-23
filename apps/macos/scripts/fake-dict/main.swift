// SPDX-License-Identifier: GPL-3.0-or-later
//
// A stand-in for the app under test, used only by the driver self-test
// (scripts/e2e-selftest.sh). It speaks the `--e2e` interface of Design/m1-tasks.md without
// any real capture: `select` steps post the fixture command, `capture` steps echo the last
// selected text as an accessibility read. Variants, chosen at compile time:
//   FAKE_WRONG     captures the wrong text, so the driver must report failures;
//   FAKE_NO_ENTRY  ignores `--e2e` and keeps running, like an app without the entry point.

import Foundation

func value(after flag: String) -> String? {
  let arguments = CommandLine.arguments
  guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
    return nil
  }
  return arguments[index + 1]
}

func runScenario(_ scenario: URL, output: URL) throws {
  let object = try JSONSerialization.jsonObject(with: Data(contentsOf: scenario))
  let steps = (object as? [String: Any])?["steps"] as? [[String: Any]] ?? []
  var results: [[String: Any]] = []
  var selected: String?
  for step in steps {
    let start = Date()
    var result: [String: Any] = ["ok": true, "failure": NSNull()]
    if let select = step["select"] as? [String: Any] {
      result["step"] = "select"
      let text = select["text"] as? String ?? ""
      DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("au.ibra.dict.fixture.command"), object: nil,
        userInfo: [
          "command": "select", "control": select["control"] as? String ?? "", "text": text,
        ],
        deliverImmediately: true)
      Thread.sleep(forTimeInterval: 0.2)
      selected = text
    } else if step["capture"] != nil {
      result["step"] = "capture"
      #if FAKE_WRONG
        let text = selected.map { String($0.reversed()) }
      #else
        let text = selected
      #endif
      if let text {
        result["source"] = "accessibility"
        result["text"] = text
      } else {
        result["ok"] = false
        result["failure"] = "unreadable"
      }
    } else if let wait = step["wait"] as? [String: Any] {
      result["step"] = "wait"
      Thread.sleep(forTimeInterval: (wait["ms"] as? Double ?? 0) / 1000)
    } else {
      result["step"] = "unknown"
      result["ok"] = false
    }
    result["ms"] = Date().timeIntervalSince(start) * 1000
    results.append(result)
  }
  let data = try JSONSerialization.data(withJSONObject: ["steps": results], options: [.sortedKeys])
  try data.write(to: output, options: .atomic)
}

#if FAKE_NO_ENTRY
  while true { Thread.sleep(forTimeInterval: 60) }
#else
  guard let scenario = value(after: "--e2e"), let output = value(after: "--e2e-out") else {
    exit(2)
  }
  do {
    try runScenario(URL(fileURLWithPath: scenario), output: URL(fileURLWithPath: output))
  } catch {
    FileHandle.standardError.write(Data("fake-dict: \(error)\n".utf8))
    exit(1)
  }
#endif
