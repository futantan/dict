// SPDX-License-Identifier: GPL-3.0-or-later
//
// The debug entry point `--e2e <scenario.json> --e2e-out <result.json>` (architecture 14.2;
// format in Design/m1-tasks.md). Compiled into debug builds only. This file holds the capture
// steps; replacement steps come with M3.
//
// `capture` calls the reader alone. `read` runs a whole "read" shortcut press through the
// real `SessionCoordinator` and result panel, with a translator that echoes the text, and
// reports when the reading panel showed and whether it was key while the fallback copied.
// `"force": "menu"` or `"key"` skips the accessibility read and copies that way, to measure
// the fallback in apps whose selection accessibility reads.

#if DEBUG
  import AppKit
  import DictCore

  enum E2EStep: Equatable, Sendable {
    case select(control: String, text: String)
    case capture(ClipboardPolicy)
    case read(force: ForcedCopy?)
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
      if let read = object["read"] as? [String: Any] {
        guard let force = read["force"] as? String else { return .read(force: nil) }
        guard let forced = ForcedCopy(rawValue: force) else {
          return .invalid("read force must be menu or key")
        }
        return .read(force: forced)
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
    case read(ms: Double, session: E2ESession.Record, report: CaptureReport?)
    case invalid(String)

    var json: Any {
      switch self {
      case .select(let ms): return ["step": "select", "ok": true, "ms": rounded(ms)]
      case .wait(let ms): return ["step": "wait", "ok": true, "ms": rounded(ms)]
      case .invalid(let reason): return ["step": "invalid", "ok": false, "error": reason]
      case .read(let ms, let session, let report):
        guard let result = session.result else {
          return ["step": "read", "ok": false, "ms": rounded(ms), "error": "no capture ran"]
        }
        var row = E2EResultRow.capture(ms: ms, result: result, report: report).json
        guard var object = row as? [String: Any] else { return row }
        object["step"] = "read"
        object["panel"] = session.panelCalls
        object["readingShownMs"] = session.readingShownMs.map(rounded) ?? NSNull()
        object["captureEndedMs"] = session.captureEndedMs.map(rounded) ?? NSNull()
        object["panelKeyAtShow"] = session.keyAtShow ?? NSNull()
        object["panelKeyAfterCopy"] = session.keyAfterCopy ?? NSNull()
        object["frontAppUnchanged"] = session.frontAppUnchanged
        row = object
        return row
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
        "copyWaitMs": copyWaitMs.map(rounded) ?? NSNull(),
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
      var session: E2ESession?
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
        case .read(let force):
          let running = session ?? E2ESession(reader: reader)
          session = running
          let record = await running.press(force: force)
          rows.append(
            .read(ms: milliseconds(clock.now - start), session: record, report: reader.lastReport))
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

  /// One "read" shortcut press through the real coordinator and panel. It stands in for the
  /// reader (to record the capture), the panel (to record what the coordinator asks of it)
  /// and the translator (which echoes the text, without any model).
  @MainActor
  final class E2ESession: SelectionReader, SessionPanel, SessionTranslator {
    struct Record {
      var result: Result<Selection, CaptureFailure>?
      /// What the coordinator asked of the panel: "show:reading@12.3", "update:result@40.1".
      var panelCalls: [String] = []
      var readingShownMs: Double?
      var captureEndedMs: Double?
      /// Whether the panel was key right after the reading panel showed, and when the copy
      /// fallback had finished.
      var keyAtShow: Bool?
      var keyAfterCopy: Bool?
      var frontAppUnchanged = true
    }

    private let reader: AccessibilitySelectionReader
    private let controller = PanelController()
    private var force: ForcedCopy?
    private var record = Record()
    private let clock = ContinuousClock()
    private var start = ContinuousClock.now
    private lazy var coordinator = SessionCoordinator(
      reader: self, panel: self,
      environment: SessionCoordinator.Environment(
        makeTranslator: { [unowned self] in self },
        languagePair: { LanguagePair() },
        refreshPermissions: {
          PermissionStatus(
            accessibility: AXIsProcessTrusted(), postEvent: CGPreflightPostEventAccess())
        },
        permissionNotice: { _ in PanelNotice(title: "permission") },
        performPermissionAction: { _ in false },
        openSettings: {},
        mouseLocation: { NSEvent.mouseLocation }))

    init(reader: AccessibilitySelectionReader) {
      self.reader = reader
    }

    /// Presses the shortcut, waits for the session to finish, then hides the panel.
    func press(force: ForcedCopy?) async -> Record {
      self.force = force
      record = Record()
      start = clock.now
      let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
      coordinator.hotkeyPressed(.read)
      await coordinator.settle()
      record.frontAppUnchanged =
        NSWorkspace.shared.frontmostApplication?.processIdentifier == front
      coordinator.end()
      // Let the target's window take key back before the next step.
      try? await Task.sleep(for: .milliseconds(100))
      return record
    }

    private var elapsed: Double { milliseconds(clock.now - start) }

    func capture(
      policy: ClipboardPolicy, beforeFallback: () -> Void
    ) async -> Result<Selection, CaptureFailure> {
      let showing = {
        beforeFallback()
        self.record.readingShownMs = self.elapsed
        self.record.keyAtShow = self.controller.window.isKeyWindow
      }
      let result =
        if let force {
          await reader.captureByCopying(force, beforeCopying: showing)
        } else {
          await reader.capture(policy: policy, beforeFallback: showing)
        }
      record.captureEndedMs = elapsed
      if record.readingShownMs != nil { record.keyAfterCopy = controller.window.isKeyWindow }
      record.result = result
      return result
    }

    var isVisible: Bool { controller.isVisible }

    func show(_ state: PanelState, near anchor: PanelAnchor) {
      controller.show(state, near: anchor)
      record.panelCalls.append(String(format: "show:%@@%.1f", state.phase.name, elapsed))
    }

    func update(_ state: PanelState) {
      controller.update(state)
      record.panelCalls.append(String(format: "update:%@@%.1f", state.phase.name, elapsed))
    }

    func hide() {
      controller.hide()
    }

    func translate(
      _ text: String, direction: Direction, pair: LanguagePair, update: (PanelState) -> Void
    ) async {
      update(PanelState(source: text, phase: .result(text)))
    }
  }
#endif
