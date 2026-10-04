// SPDX-License-Identifier: GPL-3.0-or-later
//
// Runs one scenario through the app under test's debug entry point (Design/m1-tasks.md):
//   open -g -n "<Dict Dev.app>" --args --e2e <scenario.json> --e2e-out <result.json>
// `-g` keeps the app from taking activation, so the fixture or the real app stays frontmost.
// The app runs under its own signature and Accessibility grant, not the terminal's.

import Foundation

/// One step of a result file: `{"step": "capture", "ok": true, "ms": 12.5,
/// "source": "accessibility", "text": "…", "failure": null}`.
struct StepResult {
  let step: String
  let ok: Bool
  let ms: Double?
  let source: String?
  let text: String?
  let failure: String?

  init(_ object: [String: Any]) {
    step = object["step"] as? String ?? ""
    ok = object["ok"] as? Bool ?? false
    ms = (object["ms"] as? NSNumber)?.doubleValue
    source = object["source"] as? String
    text = object["text"] as? String
    failure = object["failure"] as? String
  }
}

enum RunOutcome {
  case finished([StepResult])
  /// The app kept running without writing a result: it has no `--e2e` entry point.
  case noEntryPoint
  /// The app exited without a readable result, or never started.
  case noResult(String)
}

@MainActor
struct DictRunner {
  let app: URL
  let workDirectory: URL
  var timeout: TimeInterval = 20
  /// Passed after the entry point's own arguments, e.g. `-SomeDefault YES` (argument domain).
  var extraArguments: [String] = []
  private var counter = 0

  init(app: URL, workDirectory: URL, timeout: TimeInterval = 20) {
    self.app = app
    self.workDirectory = workDirectory
    self.timeout = timeout
  }

  /// Runs `steps` and returns the result file's steps. `during` runs once the app has started.
  mutating func run(
    _ steps: [[String: Any]], name: String, during: () -> Void = {}
  ) -> RunOutcome {
    counter += 1
    let stem = String(format: "%02d-%@", counter, name.replacingOccurrences(of: " ", with: "-"))
    let scenario = workDirectory.appendingPathComponent("\(stem).scenario.json")
    let result = workDirectory.appendingPathComponent("\(stem).result.json")
    do {
      try writeJSON(["steps": steps], to: scenario)
    } catch {
      return .noResult("could not write \(scenario.path): \(error)")
    }
    let launch = shell(
      [
        "open", "-g", "-n", app.path, "--args", "--e2e", scenario.path, "--e2e-out", result.path,
      ] + extraArguments)
    guard launch.status == 0 else { return .noResult("open failed with status \(launch.status)") }

    let launched: [pid_t] =
      poll(timeout: 3) { () -> [pid_t]? in
        let found = pids(matching: "--e2e-out \(result.path)")
        return found.isEmpty ? nil : found
      } ?? []
    if !launched.isEmpty { during() }
    func readResult() -> [StepResult]? {
      guard let object = readJSON(result) as? [String: Any],
        let steps = object["steps"] as? [[String: Any]]
      else { return nil }
      return steps.map(StepResult.init)
    }
    // Wait for a result, or for the app to exit without one.
    _ = poll(timeout: timeout) {
      readResult() != nil || !launched.contains(where: isRunning) ? true : nil
    }
    let parsed = readResult()
    // The app should exit by itself once it has written the result; make sure it does.
    let exited = poll(timeout: parsed == nil ? 0 : 5) {
      launched.contains(where: isRunning) ? nil : true
    }
    let leftover = launched.filter(isRunning)
    for pid in leftover { terminate(pid) }

    if let parsed { return .finished(parsed) }
    if exited == nil && !leftover.isEmpty { return .noEntryPoint }
    if launched.isEmpty { return .noResult("the app did not start") }
    return .noResult("the app exited without writing \(result.lastPathComponent)")
  }

  /// Runs an empty scenario to find out whether the app has the `--e2e` entry point at all.
  mutating func probe() -> RunOutcome {
    let saved = timeout
    timeout = min(timeout, 10)
    defer { timeout = saved }
    return run([], name: "probe")
  }
}
