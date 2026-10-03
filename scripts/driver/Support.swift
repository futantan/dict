// SPDX-License-Identifier: GPL-3.0-or-later
//
// Small helpers shared by the e2e, matrix and self-test drivers: processes, waiting, JSON,
// cleanup on every exit path.

import AppKit
import Foundation

struct DriverError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

func say(_ message: String) {
  print(message)
  fflush(stdout)
}

/// Waits while letting the main run loop run, so signal handlers on the main queue fire.
@MainActor
func pause(_ seconds: TimeInterval) {
  RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
}

/// Polls `condition` every 50 ms until it returns a value or `timeout` passes.
@MainActor
func poll<T>(timeout: TimeInterval, _ condition: () -> T?) -> T? {
  let deadline = Date(timeIntervalSinceNow: timeout)
  repeat {
    if let value = condition() { return value }
    pause(0.05)
  } while Date() < deadline
  return condition()
}

/// Runs a command to completion and returns its exit status and standard output.
@discardableResult
func shell(_ arguments: [String]) -> (status: Int32, output: String) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = arguments
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = FileHandle.nullDevice
  do { try process.run() } catch { return (-1, "") }
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

/// Pids whose full command line contains `pattern` (a fixed string).
func pids(matching pattern: String) -> [pid_t] {
  let escaped = NSRegularExpression.escapedPattern(for: pattern)
  return shell(["pgrep", "-f", "--", escaped]).output.split(separator: "\n").compactMap {
    pid_t($0)
  }
}

func isRunning(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

/// SIGTERM, then SIGKILL after `grace` seconds.
@MainActor
func terminate(_ pid: pid_t, grace: TimeInterval = 3) {
  guard isRunning(pid) else { return }
  kill(pid, SIGTERM)
  if poll(timeout: grace, { isRunning(pid) ? nil : true }) == nil { kill(pid, SIGKILL) }
}

func readJSON(_ url: URL) -> Any? {
  guard let data = try? Data(contentsOf: url) else { return nil }
  return try? JSONSerialization.jsonObject(with: data)
}

func writeJSON(_ object: Any, to url: URL) throws {
  let data = try JSONSerialization.data(
    withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
  try (data + Data("\n".utf8)).write(to: url)
}

/// Cleanup actions that must run on every exit path: normal end, failure, SIGINT, SIGTERM.
/// They run in reverse order of registration.
@MainActor
enum Cleanup {
  private static var actions: [(id: Int, run: () -> Void)] = []
  private static var nextID = 0
  private static var signalSources: [DispatchSourceSignal] = []

  @discardableResult
  static func add(_ action: @escaping () -> Void) -> Int {
    nextID += 1
    actions.append((nextID, action))
    return nextID
  }

  /// Runs one action now and forgets it.
  static func run(_ id: Int) {
    guard let index = actions.firstIndex(where: { $0.id == id }) else { return }
    actions.remove(at: index).run()
  }

  static func runAll() {
    while let action = actions.popLast() { action.run() }
  }

  static func installSignalHandlers() {
    for number in [SIGINT, SIGTERM, SIGHUP] {
      signal(number, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
      source.setEventHandler {
        MainActor.assumeIsolated {
          say("driver: interrupted, cleaning up")
          runAll()
          exit(130)
        }
      }
      source.resume()
      signalSources.append(source)
    }
  }
}

/// UI tests cannot take focus or validate menus while the screen is locked.
func screenIsLocked() -> Bool {
  let session = CGSessionCopyCurrentDictionary() as? [String: Any]
  return session?["CGSSessionScreenIsLocked"] as? Bool == true
}

func requireUnlockedScreen() throws {
  guard !screenIsLocked() else {
    throw DriverError("the screen is locked; UI tests need an unlocked, logged-in session")
  }
}

/// The JSON Lines event log written by CaptureFixture.
struct FixtureLogEntry {
  let control: String
  let event: String
  let detail: String
}

func readFixtureLog(_ url: URL) -> [FixtureLogEntry] {
  guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
  return text.split(separator: "\n").compactMap { line in
    guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    else { return nil }
    return FixtureLogEntry(
      control: object["control"] as? String ?? "", event: object["event"] as? String ?? "",
      detail: object["detail"] as? String ?? "")
  }
}
