// SPDX-License-Identifier: GPL-3.0-or-later
//
// `make e2e` (architecture 14.3, acceptance 15.1 item 2): for each scenario the fixture is
// brought to the front, the app under test runs `select` then `capture` through its `--e2e`
// entry point, and the driver checks the captured text, source or failure, the fixture's
// copy and paste events, and that the clipboard hash is unchanged. A `write` scenario presses
// the write shortcut instead, confirms with Return and undoes with ⌘Z, and is checked on the
// panel's last state, the field's value after each, and the fixture's accessibility write.

import Foundation

struct E2EScenario: Decodable {
  struct Expectation: Decodable {
    var source: String?
    var text: String?
    /// A `CaptureFailure` case name; when set, the capture must fail with it.
    var failure: String?
    var copyEvents: Int?
    /// `read` scenarios: whether the reading panel must show before the clipboard fallback
    /// (true) or not at all (false).
    var readingPanel: Bool?
    /// The context sentence the capture must read around the selection.
    var context: String?
    /// `read` scenarios: what the panel ended on, "card" (complete) or "translation".
    var kind: String?
    /// `read` scenarios with `kind` "card": the card's title.
    var lemma: String?
    /// `write` scenarios: the panel's phase before Return, e.g. "translatedOut".
    var phase: String?
    /// `write` scenarios: whether a back-translation showed before Return.
    var backTranslation: Bool?
    /// `write` scenarios: the field's whole value after Return, and after ⌘Z.
    var replaced: String?
    var undone: String?
  }

  var name: String
  var control: String
  var text: String
  var content: String?
  var policy: String
  /// "capture" (default) calls the reader; "read" presses the shortcut through the
  /// coordinator and the real panel; "write" presses the write shortcut, then Return and ⌘Z.
  var step: String?
  /// For "read": "menu" or "key" forces that copy path.
  var force: String?
  var expect: Expectation
}

struct E2EScenarioFile: Decodable {
  var scenarios: [E2EScenario]
}

struct ScenarioOutcome {
  enum Status: String { case pass = "PASS", fail = "FAIL", skip = "SKIP" }
  let name: String
  let status: Status
  let notes: [String]
  var ms: Double? = nil

  var line: String {
    let timing = ms.map { String(format: " (capture %.1f ms)", $0) } ?? ""
    let details = notes.isEmpty ? "" : ": " + notes.joined(separator: "; ")
    return "\(status.rawValue)  \(name)\(timing)\(details)"
  }
}

struct E2EReport {
  var outcomes: [ScenarioOutcome] = []
  var entryPoint: String = ""

  func count(_ status: ScenarioOutcome.Status) -> Int {
    outcomes.filter { $0.status == status }.count
  }
  var passed: Bool { !outcomes.isEmpty && outcomes.allSatisfy { $0.status == .pass } }
  var summary: String {
    "\(count(.pass)) passed, \(count(.fail)) failed, \(count(.skip)) skipped"
  }
}

@MainActor
struct E2E {
  let app: URL
  let fixtureApp: URL
  let scenarios: [E2EScenario]
  let workDirectory: URL
  /// The self-test's fake apps capture nothing, so they can run on a locked screen.
  var needsUnlockedScreen = true

  static func loadScenarios(_ url: URL) throws -> [E2EScenario] {
    try JSONDecoder().decode(E2EScenarioFile.self, from: Data(contentsOf: url)).scenarios
  }

  /// Runs every scenario, holding the UI lock and guarding the clipboard throughout.
  func run() throws -> E2EReport {
    try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    var runner = DictRunner(app: app, workDirectory: workDirectory)
    var report = E2EReport()

    // The probe launches the app in the background only; it needs no lock.
    switch runner.probe() {
    case .finished:
      report.entryPoint = "present"
    case .noEntryPoint:
      report.entryPoint =
        "not implemented: \(app.lastPathComponent) kept running without writing a result "
        + "(the --e2e entry point is M1.4's)"
      report.outcomes = scenarios.map {
        ScenarioOutcome(name: $0.name, status: .skip, notes: ["no --e2e entry point"])
      }
      return report
    case .noResult(let reason):
      report.entryPoint = "broken: \(reason)"
      report.outcomes = scenarios.map {
        ScenarioOutcome(name: $0.name, status: .fail, notes: ["probe failed: \(reason)"])
      }
      return report
    }

    if needsUnlockedScreen { try requireUnlockedScreen() }
    try UILock.with("make e2e") {
      try Clipboard.guarded {
        let fixture = Fixture(
          app: fixtureApp, log: workDirectory.appendingPathComponent("fixture.jsonl"))
        try fixture.launch()
        for scenario in scenarios {
          let outcome = runScenario(scenario, fixture: fixture, runner: &runner)
          say(outcome.line)
          report.outcomes.append(outcome)
        }
      }
    }
    return report
  }

  private func runScenario(
    _ scenario: E2EScenario, fixture: Fixture, runner: inout DictRunner
  ) -> ScenarioOutcome {
    fixture.activate()
    let hashBefore = Clipboard.hash()
    let typesBefore = Clipboard.describe()
    let mark = fixture.mark
    var select: [String: Any] = ["control": scenario.control, "text": scenario.text]
    select["content"] = scenario.content
    let action: [String: Any] =
      switch scenario.step {
      case "read": ["read": scenario.force.map { ["force": $0] } ?? [:]]
      case "write": ["write": [String: Any]()]
      default: ["capture": ["policy": scenario.policy]]
      }
    let outcome = runner.run([["select": select], action], name: scenario.name)
    let events = fixture.entries(since: mark)
    var notes: [String] = []
    var ms: Double?

    if Clipboard.hash() != hashBefore {
      notes.append("clipboard hash changed: types \(typesBefore) became \(Clipboard.describe())")
    }
    let selected = events.first { $0.event == "select" && $0.control == scenario.control }
    if let selected, selected.detail.hasPrefix("error:") {
      notes.append("fixture could not select: \(selected.detail)")
    } else if selected == nil {
      notes.append("the fixture never received the select command")
    }
    let copies = events.filter { $0.event == "copy" }.count
    let pastes = events.filter { $0.event == "paste" }.count
    let expectedCopies = scenario.expect.copyEvents ?? 0
    if copies != expectedCopies {
      notes.append("copy events \(copies), expected \(expectedCopies)")
    }
    if pastes != 0 { notes.append("paste events \(pastes), expected 0") }

    switch outcome {
    case .noEntryPoint:
      notes.append("no --e2e entry point")
    case .noResult(let reason):
      notes.append(reason)
    case .finished(let steps):
      if let capture = steps.last(where: { ["capture", "read", "write"].contains($0.step) }) {
        // A `read` step's own ms includes showing the panel and letting it settle.
        ms = capture.captureEndedMs ?? capture.ms
        notes += check(capture, against: scenario.expect)
      } else {
        notes.append("the result has no capture step")
      }
    }
    return ScenarioOutcome(
      name: scenario.name, status: notes.isEmpty ? .pass : .fail, notes: notes, ms: ms)
  }

  private func check(_ capture: StepResult, against expect: E2EScenario.Expectation) -> [String] {
    let got =
      capture.ok
      ? "ok, source \(capture.source ?? "nil"), \(Self.quote(capture.text))"
      : "failure \(capture.failure ?? "nil")"
    var notes: [String] = []
    switch expect.readingPanel {
    case true?: notes += capture.readingPanelProblems
    case false?:
      if let shown = capture.readingShownMs { notes.append("reading panel shown at \(shown) ms") }
    case nil: break
    }
    if let failure = expect.failure {
      if capture.ok || capture.failure != failure {
        notes.append("expected failure \(failure), got \(got)")
      }
      return notes
    }
    guard capture.ok else { return notes + ["expected success, got \(got)"] }
    if let source = expect.source, capture.source != source {
      notes.append("expected source \(source), got \(capture.source ?? "nil")")
    }
    if let text = expect.text, capture.text != text {
      notes.append("expected text \(Self.quote(text)), got \(Self.quote(capture.text))")
    }
    if let context = expect.context, capture.context != context {
      notes.append(
        "expected context \(Self.quote(context)), got \(Self.quote(capture.context))")
    }
    notes += Self.panelProblems(capture.translation, against: expect)
    if capture.step == "write" { notes += Self.writeProblems(capture.write, against: expect) }
    return notes
  }

  /// What a `write` step's panel showed and what the field held after Return and ⌘Z.
  static func writeProblems(_ write: [String: Any], against expect: E2EScenario.Expectation)
    -> [String]
  {
    var notes: [String] = []
    if let phase = expect.phase, write["phase"] as? String != phase {
      notes.append("expected the panel in \(phase), got \(write["phase"] as? String ?? "nil")")
    }
    if let back = expect.backTranslation, (write["backTranslation"] as? String != nil) != back {
      notes.append(back ? "no back-translation before Return" : "an unexpected back-translation")
    }
    if let replaced = expect.replaced, write["valueAfterReplace"] as? String != replaced {
      notes.append(
        "expected \(quote(replaced)) after Return, got "
          + "\(quote(write["valueAfterReplace"] as? String)) (toast \(write["toast"] ?? "nil"))")
    }
    if let undone = expect.undone, write["valueAfterUndo"] as? String != undone {
      notes.append(
        "expected \(quote(undone)) after ⌘Z, got \(quote(write["valueAfterUndo"] as? String))")
    }
    if write["visibleAtEnd"] as? Bool == true { notes.append("the panel stayed after Return") }
    return notes
  }

  /// What a `read` step's panel ended on, against `kind` and `lemma`.
  static func panelProblems(_ panel: [String: Any], against expect: E2EScenario.Expectation)
    -> [String]
  {
    let phase = panel["phase"] as? String
    var notes: [String] = []
    switch expect.kind {
    case "card"?:
      let model = panel["cardModel"] as? String
      if phase != "card" || model != "complete" {
        notes.append("expected a complete card, got \(phase ?? "nil") \(model ?? "")")
      }
    case "translation"?:
      if phase != "result" { notes.append("expected a translation, got \(phase ?? "nil")") }
    case let kind?:
      notes.append("unknown kind \(kind)")
    case nil:
      break
    }
    if let lemma = expect.lemma, panel["lemma"] as? String != lemma {
      notes.append(
        "expected lemma \(quote(lemma)), got \(quote(panel["lemma"] as? String))")
    }
    return notes
  }

  static func quote(_ text: String?) -> String {
    guard let text else { return "nil" }
    let escaped = text.replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
  }
}
