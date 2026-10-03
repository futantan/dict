// SPDX-License-Identifier: GPL-3.0-or-later
//
// The debug entry point `--e2e <scenario.json> --e2e-out <result.json>` (architecture 14.2;
// format in Design/m1-tasks.md). Compiled into debug builds only. This file holds the capture
// steps; replacement steps come with M3.

#if DEBUG
  import AppKit

  enum E2EStep: Equatable, Sendable {
    case select(control: String, text: String)
    case capture(ClipboardPolicy)
    case wait(ms: Int)
    /// A step this runner does not understand; reported, then skipped.
    case invalid(String)
  }

  enum E2EScenario {
    struct FormatError: Error {}

    static func parse(_ data: Data) throws -> [E2EStep] {
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let steps = root["steps"] as? [[String: Any]]
      else { throw FormatError() }
      return steps.map(step)
    }

    private static func step(_ object: [String: Any]) -> E2EStep {
      if let select = object["select"] as? [String: Any] {
        guard let control = select["control"] as? String, let text = select["text"] as? String
        else { return .invalid("select needs control and text") }
        return .select(control: control, text: text)
      }
      if let capture = object["capture"] as? [String: Any] {
        switch capture["policy"] as? String {
        case "allowed": return .capture(.allowed)
        case "never": return .capture(.never)
        default: return .invalid("capture policy must be allowed or never")
        }
      }
      if let wait = object["wait"] as? [String: Any] {
        guard let ms = wait["ms"] as? Int else { return .invalid("wait needs ms") }
        return .wait(ms: ms)
      }
      return .invalid("unknown step")
    }
  }

  enum E2EResultRow {
    case select(ms: Double)
    case wait(ms: Double)
    case capture(
      ms: Double, result: Result<Selection, CaptureFailure>, report: CaptureReport? = nil)
    case invalid(String)

    var json: Any {
      switch self {
      case .select(let ms): return ["step": "select", "ok": true, "ms": rounded(ms)]
      case .wait(let ms): return ["step": "wait", "ok": true, "ms": rounded(ms)]
      case .invalid(let reason): return ["step": "invalid", "ok": false, "error": reason]
      case .capture(let ms, let result, let report):
        var row: [String: Any] = ["step": "capture", "ms": rounded(ms)]
        switch result {
        case .success(let selection):
          row["ok"] = true
          row["source"] = selection.source.caseName
          row["text"] = selection.text
          row["failure"] = NSNull()
          row["app"] = selection.app?.bundleID ?? NSNull()
          row["context"] = selection.context?.sentence ?? NSNull()
          row["bounds"] =
            selection.bounds.map { [$0.minX, $0.minY, $0.width, $0.height] } ?? NSNull()
        case .failure(let failure):
          row["ok"] = false
          row["source"] = NSNull()
          row["text"] = NSNull()
          row["failure"] = failure.caseName
          row["failureDetail"] = failure.logDescription
        }
        if let report { row["stages"] = report.json }
        return row
      }
    }

    static func document(_ rows: [E2EResultRow], error: String? = nil) throws -> Data {
      var root: [String: Any] = ["steps": rows.map(\.json)]
      if let error { root["error"] = error }
      return try JSONSerialization.data(
        withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }
  }

  private func rounded(_ ms: Double) -> Double { (ms * 10).rounded() / 10 }

  extension CaptureReport {
    var json: [String: Any] {
      [
        "app": bundleID ?? NSNull(),
        "kind": kind.map { "\($0)" } ?? NSNull(),
        "warmup": warmup.map { "\($0)" } ?? NSNull(),
        "attempts": attempts,
        "firstStageMs": firstStageMs.map(rounded) ?? NSNull(),
        "secondStageMs": secondStageMs.map(rounded) ?? NSNull(),
        "fallbackMs": fallbackMs.map(rounded) ?? NSNull(),
      ]
    }
  }

  @MainActor
  enum E2ERunner {
    static let fixtureCommand = Notification.Name("au.ibra.dict.fixture.command")

    /// Starts the scenario once the app runs, if both arguments are present; the app quits
    /// when it is done (through `terminate`, so quit-time clean-up still runs).
    static func startIfRequested(arguments: [String] = CommandLine.arguments) {
      guard let scenario = value(after: "--e2e", in: arguments),
        let output = value(after: "--e2e-out", in: arguments)
      else { return }
      Task {
        await run(scenario: URL(fileURLWithPath: scenario), output: URL(fileURLWithPath: output))
        NSApp.terminate(nil)
      }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
      guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
      else { return nil }
      return arguments[index + 1]
    }

    static func run(scenario: URL, output: URL) async {
      let steps: [E2EStep]
      do {
        steps = try E2EScenario.parse(Data(contentsOf: scenario))
      } catch {
        write([], error: "cannot read scenario: \(error)", to: output)
        return
      }
      let reader = AccessibilitySelectionReader()
      reader.start()
      var rows: [E2EResultRow] = []
      for step in steps {
        let clock = ContinuousClock()
        let start = clock.now
        switch step {
        case .select(let control, let text):
          DistributedNotificationCenter.default().postNotificationName(
            fixtureCommand, object: nil,
            userInfo: ["command": "select", "control": control, "text": text],
            deliverImmediately: true)
          try? await Task.sleep(for: .milliseconds(200))
          rows.append(.select(ms: milliseconds(clock.now - start)))
        case .wait(let ms):
          try? await Task.sleep(for: .milliseconds(ms))
          rows.append(.wait(ms: milliseconds(clock.now - start)))
        case .capture(let policy):
          let result = await reader.capture(policy: policy)
          rows.append(
            .capture(
              ms: milliseconds(clock.now - start), result: result, report: reader.lastReport))
        case .invalid(let reason):
          rows.append(.invalid(reason))
        }
      }
      write(rows, error: nil, to: output)
    }

    private static func write(_ rows: [E2EResultRow], error: String?, to output: URL) {
      do {
        try E2EResultRow.document(rows, error: error).write(to: output, options: .atomic)
      } catch {
        Log.capture.error("e2e: cannot write the result: \(error, privacy: .public)")
      }
    }
  }
#endif
