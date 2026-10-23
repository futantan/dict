// SPDX-License-Identifier: GPL-3.0-or-later
//
// `make e2e-live` (acceptance 15.1 items 4–6): the whole "read" shortcut press with the real
// model — capture, panel, streamed translation — in real apps, through the app's `--e2e`
// entry point. The press is the coordinator's entry point called inside Dict, not a key
// typed on the keyboard. It uses the saved model settings and the Keychain key of the app
// under test (`make import-key`), so it costs money and needs the network; it is never part
// of `make test` or `make e2e`.
//
// Failure rows point the model at a port that refuses connections, a rejected key, or
// scripts/fake-model.py (a stalled stream, a stream cut off, a slow stream for Esc and a
// second press). At the end the app's log of the run is checked for the test sentences and
// for the key, reporting only counts.
//
// House rules as in Matrix.swift: each section holds the UI lock and guards the clipboard;
// only the driver's own tabs and windows are closed; Chrome's AXEnhancedUserInterface is
// restored.

import AppKit
import NaturalLanguage

@MainActor
struct Live {
  static let sections = ["fixture", "textedit", "safari", "chrome"]
  static let english = "The weather is lovely today, so we are going for a walk by the river."
  static let chinese = "会议改到明天下午三点，请提前十分钟到达会议室。"
  static let fixtureEnglish = "Please remember to bring your umbrella because it may rain later."
  /// A long paragraph, to see the panel keep up with a long stream.
  static let paragraph = [
    "The library on the corner opened in 1923 and has been rebuilt twice since then.",
    "Its reading room faces the harbour, so in the afternoon the light comes in low and warm.",
    "Most visitors come for the local newspapers, which go back more than a hundred years.",
    "The staff will help you find an article if you know roughly when it was printed.",
    "On Saturdays there is a small market outside selling bread, honey and second-hand books.",
    "Children's story time starts at ten, and it is usually full by a quarter to ten.",
    "If you plan to stay all day, bring a jumper, because the old building is often cold.",
    "The café next door closes at four, but the library itself stays open until eight.",
  ].joined(separator: " ")
  static let fakeModelPort = 8766
  /// A key the provider rejects; not a secret.
  static let rejectedKey = "sk-dict-e2e-rejected-0000000000000000"

  let app: URL
  let fixtureApp: URL
  let pages: URL
  let work: URL
  let only: [String]?
  let runs: Int
  private var runner: DictRunner
  private var rows: [LiveRow] = []

  init(app: URL, fixtureApp: URL, pages: URL, work: URL, only: [String]?, runs: Int) {
    self.app = app
    self.fixtureApp = fixtureApp
    self.pages = pages
    self.work = work
    self.only = only
    self.runs = runs
    runner = DictRunner(app: app, workDirectory: work, timeout: 180)
  }

  mutating func run() throws -> Int32 {
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    guard case .finished = runner.probe() else {
      throw DriverError("the --e2e entry point of \(app.lastPathComponent) did not answer")
    }
    try requireUnlockedScreen()
    try startPageServer(pages)
    try startFakeModel()
    let started = Date()
    for section in only ?? Self.sections {
      guard Self.sections.contains(section) else { throw DriverError("unknown section \(section)") }
      say("live: \(section)")
      try UILock.with("make e2e-live \(section)") {
        try Clipboard.guarded {
          switch section {
          case "fixture": try fixture()
          case "textedit": try textEdit()
          case "safari": try safari()
          default: try chrome()
          }
        }
      }
    }
    summarize()
    let logProblems = checkLog(since: started)
    let failed = rows.filter { !$0.problems.isEmpty }.count
    say("live: \(rows.count - failed) passed, \(failed) failed, \(logProblems) log problems")
    return failed == 0 && logProblems == 0 ? 0 : 1
  }

  // MARK: Steps

  static func modelRead(_ extra: [String: Any] = [:]) -> [String: Any] {
    ["read": extra.merging(["translator": "model"]) { a, _ in a }]
  }

  static func fakeModel(_ mode: String) -> String {
    "http://127.0.0.1:\(fakeModelPort)/\(mode)/v1"
  }

  /// Runs `steps` in one Dict process and checks every `read` step against `expect`.
  private mutating func reads(
    _ name: String, steps: [[String: Any]], expect: LiveExpectation,
    prepare: () -> Bool = { true }
  ) {
    let before = Clipboard.hash()
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let outcome = runner.run(steps, name: name)
    let clipboardIntact = Clipboard.hash() == before
    let frontIntact = NSWorkspace.shared.frontmostApplication?.processIdentifier == front
    let results: [StepResult]
    var problems: [String] = []
    switch outcome {
    case .finished(let steps): results = steps.filter { $0.step == "read" }
    case .noEntryPoint: results = []; problems.append("no --e2e entry point")
    case .noResult(let reason): results = []; problems.append(reason)
    }
    if results.isEmpty && problems.isEmpty { problems.append("no read step in the result") }
    if !clipboardIntact { problems.append("clipboard changed") }
    if !frontIntact { problems.append("the front app changed") }
    for (index, step) in results.enumerated() {
      var row = LiveRow(name: results.count > 1 ? "\(name) #\(index + 1)" : name, step: step)
      row.problems = problems + expect.problems(step)
      say("  " + row.line)
      rows.append(row)
    }
    if results.isEmpty {
      var row = LiveRow(name: name, step: nil)
      row.problems = problems
      say("  " + row.line)
      rows.append(row)
    }
  }

  // MARK: Sections

  /// CaptureFixture: a custom view read through the clipboard fallback, Chinese into English,
  /// and every failure row.
  private mutating func fixture() throws {
    let fixture = Fixture(app: fixtureApp, log: work.appendingPathComponent("fixture.jsonl"))
    try fixture.launch()
    func select(_ control: String, _ text: String) -> [String: Any] {
      ["select": ["control": control, "text": text, "content": text]]
    }
    func row(
      _ name: String, _ control: String, _ text: String, _ read: [String: Any],
      _ expect: LiveExpectation
    ) {
      fixture.activate()
      reads(name, steps: [select(control, text), read], expect: expect)
    }
    let english = Self.fixtureEnglish
    row(
      "fixture custom view (fallback), en → zh", "custom.noSelectedText", english,
      Self.modelRead(), .result(language: .simplifiedChinese, source: "menuCopy"))
    row(
      "fixture text view, zh → en", "textView.plain", Self.chinese, Self.modelRead(),
      .result(language: .english, source: "accessibility"))
    row(
      "fixture text view, long paragraph en → zh", "textView.plain", Self.paragraph,
      Self.modelRead(), .result(language: .simplifiedChinese, source: "accessibility"))
    row(
      "fixture, second press while reading the selection", "textView.plain", english,
      Self.modelRead(["pressAgainAfterMs": 0]),
      .result(language: .simplifiedChinese, source: "accessibility", secondPress: "panel hidden"))
    row(
      "fixture, connection refused", "textView.plain", english,
      Self.modelRead(["baseURL": "http://127.0.0.1:1/v1"]),
      .failure(actions: ["translation.retry"]))
    row(
      "fixture, rejected key", "textView.plain", english,
      Self.modelRead(["apiKey": Self.rejectedKey]),
      .failure(actions: ["translation.openSettings"]))
    row(
      "fixture, stalled stream (first-event timeout)", "textView.plain", english,
      Self.modelRead(["baseURL": Self.fakeModel("hang")]),
      .failure(actions: ["translation.retry"], minimumMs: 9_500))
    row(
      "fixture, stream cut off", "textView.plain", english,
      Self.modelRead(["baseURL": Self.fakeModel("cut")]),
      .partial(text: "部分译文", noteAction: "translation.retry"))
    row(
      "fixture, Esc while streaming", "textView.plain", english,
      Self.modelRead(["baseURL": Self.fakeModel("slow"), "escapeAfterMs": 1_200]),
      .cancelled(by: "escape"))
    row(
      "fixture, second press while streaming", "textView.plain", english,
      Self.modelRead(["baseURL": Self.fakeModel("slow"), "pressAgainAfterMs": 1_200]),
      .cancelled(by: "press"))
  }

  /// TextEdit: the same English sentence `runs` times in one Dict process (the latency rows),
  /// then a Chinese sentence.
  private mutating func textEdit() throws {
    let bundleID = "com.apple.TextEdit"
    let wasRunning = !runningPids(bundleID).isEmpty
    let file = work.appendingPathComponent("dict-live-textedit.txt")
    let content = Self.english + "\n" + Self.chinese
    try content.write(to: file, atomically: true, encoding: .utf8)
    shell(["open", "-a", "TextEdit", file.path])
    guard let pid = poll(timeout: 10, { runningPids(bundleID).first }),
      let window = poll(timeout: 10, { findWindow(pid, titled: "dict-live-textedit") })
    else { throw DriverError("the TextEdit window did not appear") }
    defer {
      if let close = AX.element(AX.attribute(window, kAXCloseButtonAttribute)) { AX.press(close) }
      if !wasRunning { quit(pid) }
    }
    pause(0.5)
    for (sentence, language, count) in [
      (Self.english, NLLanguage.simplifiedChinese, runs), (Self.chinese, .english, 1),
    ] {
      guard let text = AX.focusedElement(pid), selectRange(text, of: sentence, in: content) else {
        throw DriverError("could not select the TextEdit text through accessibility")
      }
      reads(
        "TextEdit \(language == .english ? "zh → en" : "en → zh")",
        steps: Array(repeating: Self.modelRead(), count: count),
        expect: .result(language: language, source: "accessibility"))
    }
  }

  private mutating func safari() throws {
    let bundleID = "com.apple.Safari"
    let wasRunning = !runningPids(bundleID).isEmpty
    let control = "web.paragraph"
    let url = fixturePageURL(control, text: Self.english, content: Self.english)
    guard let pid = openFixturePage(url, control: control, in: "Safari", bundleID: bundleID) else {
      throw DriverError("the Safari page did not load")
    }
    reads(
      "Safari read-only page, en → zh", steps: [Self.modelRead()],
      expect: .result(language: .simplifiedChinese, source: "accessibility"))
    closeFixtureTab(pid, control: control)
    if !wasRunning { quit(pid) }
  }

  /// The user's own Chrome: one test tab, closed afterwards; AXEnhancedUserInterface and the
  /// tab count are checked before and after.
  private mutating func chrome() throws {
    let bundleID = "com.google.Chrome"
    guard let pid = runningPids(bundleID).first else {
      throw DriverError("Chrome is not running; this row uses the user's own Chrome")
    }
    let attribute = "AXEnhancedUserInterface"
    let original = AX.attribute(AX.app(pid), attribute) as? Bool
    let tabsBefore = chromeTabCount(pid)
    say("  Chrome \(attribute) was \(original.map(String.init) ?? "unset"), \(tabsBefore) tabs")
    let restore = Cleanup.add {
      _ = AX.set(AX.app(pid), attribute, (original ?? false) as CFBoolean)
    }
    defer {
      Cleanup.run(restore)
      let now = AX.attribute(AX.app(pid), attribute) as? Bool
      say(
        "  Chrome \(attribute) restored to \(now.map(String.init) ?? "unset"), "
          + "\(chromeTabCount(pid)) tabs")
    }
    let control = "web.paragraph"
    let url = fixturePageURL(control, text: Self.english, content: Self.english)
    guard openFixturePage(url, control: control, in: "Google Chrome", bundleID: bundleID) != nil
    else { throw DriverError("the Chrome page did not load") }
    reads(
      "Chrome page, en → zh", steps: [Self.modelRead()],
      expect: .result(language: .simplifiedChinese, source: nil))
    closeFixtureTab(pid, control: control)
  }

  /// Tabs across Chrome's windows, counted from the tab groups' radio buttons.
  private func chromeTabCount(_ pid: pid_t) -> Int {
    func count(_ element: AXUIElement, depth: Int) -> Int {
      guard depth < 8 else { return 0 }
      if AX.string(element, kAXRoleAttribute) == kAXTabGroupRole as String {
        return AX.children(element).filter {
          AX.string($0, kAXRoleAttribute) == kAXRadioButtonRole as String
        }.count
      }
      return AX.children(element).reduce(0) { $0 + count($1, depth: depth + 1) }
    }
    return AX.windows(pid).reduce(0) { $0 + count($1, depth: 0) }
  }

  // MARK: Fake model

  private func startFakeModel() throws {
    // scripts/e2e-live.sh runs the driver from the repository root.
    let script = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("scripts/fake-model.py")
    let server = Process()
    server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    server.arguments = [script.path, String(Self.fakeModelPort)]
    server.standardOutput = FileHandle.nullDevice
    server.standardError = FileHandle.nullDevice
    try server.run()
    Cleanup.add { server.terminate() }
    let probe = [
      "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "-X", "POST",
      "http://127.0.0.1:\(Self.fakeModelPort)/unknown",
    ]
    guard poll(timeout: 10, { shell(probe).output == "404" ? true : nil }) != nil else {
      throw DriverError("the fake model on port \(Self.fakeModelPort) did not start")
    }
  }

  // MARK: Report

  private func summarize() {
    let latency = rows.filter { $0.name.hasPrefix("TextEdit en → zh") }.compactMap(\.step)
    guard !latency.isEmpty else { return }
    func median(_ values: [Double]) -> String {
      let sorted = values.sorted()
      guard !sorted.isEmpty else { return "-" }
      let middle = sorted.count / 2
      let value =
        sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
      return String(format: "%.1f", value)
    }
    let shown = latency.compactMap(\.panelShownMs)
    let first = latency.compactMap(\.firstTextMs)
    let ended = latency.compactMap(\.endedMs)
    say(
      "live: TextEdit en → zh, \(latency.count) presses in one Dict process; medians from the "
        + "press: panel \(median(shown)) ms, first text \(median(first)) ms, done "
        + "\(median(ended)) ms")
    say(
      "live: without the process's first press: panel \(median(Array(shown.dropFirst()))) ms, "
        + "first text \(median(Array(first.dropFirst()))) ms, done "
        + "\(median(Array(ended.dropFirst()))) ms")
    say(
      "live: first text per press (ms): "
        + first.map { String(format: "%.0f", $0) }.joined(separator: ", "))
  }

  /// Counts the app's log lines of this run that carry a test sentence's words or a part of
  /// the key; prints counts only. Returns the number of problems.
  private func checkLog(since started: Date) -> Int {
    let minutes = Int(Date().timeIntervalSince(started) / 60) + 2
    let subsystem = Bundle(url: app)?.bundleIdentifier ?? "au.ibra.dict.dev"
    let log = shell([
      "/usr/bin/log", "show", "--last", "\(minutes)m", "--info", "--predicate",
      "subsystem == \"\(subsystem)\"",
    ]).output
    let lines = log.split(separator: "\n").map(String.init)
    let words = [
      "weather", "lovely", "umbrella", "river", "会议", "明天", "Please remember", "词",
      "部分", "天气", "雨伞",
    ]
    var problems = 0
    let wordHits = words.map { word in lines.filter { $0.contains(word) }.count }
    say("live: log lines containing test words: \(wordHits.reduce(0, +)) (per word \(wordHits))")
    problems += wordHits.filter { $0 > 0 }.count
    for (label, part) in keyParts() {
      let hits = lines.filter { $0.contains(part) }.count
      say("live: log lines containing the key's \(label): \(hits)")
      if hits > 0 { problems += 1 }
    }
    let rejected = lines.filter { $0.contains(Self.rejectedKey) }.count
    say("live: log lines containing the rejected test key: \(rejected)")
    if rejected > 0 { problems += 1 }
    for marker in [
      "capture ", "panel shown", "first text", "ended in", "translation engine: model",
      "model translation failed", "cancelled",
    ] {
      say("live: log lines with \"\(marker)\": \(lines.filter { $0.contains(marker) }.count)")
    }
    return problems
  }

  /// The first and last eight characters of OPENAI_API_KEY in the repository's .env, read
  /// here so the key never reaches a command line.
  private func keyParts() -> [(String, String)] {
    let env = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(".env")
    guard let text = try? String(contentsOf: env, encoding: .utf8) else { return [] }
    let line = text.split(separator: "\n").last { $0.contains("OPENAI_API_KEY=") }
    guard let line, let equals = line.firstIndex(of: "=") else { return [] }
    let key = line[line.index(after: equals)...].trimmingCharacters(
      in: CharacterSet(charactersIn: "\"' ").union(.whitespaces))
    guard key.count > 16 else { return [] }
    // "sk-proj-" is shared by every project key, so the prefix skips it.
    let prefix = String(key.dropFirst(8).prefix(8))
    return [("prefix", prefix), ("suffix", String(key.suffix(8)))]
  }
}

// MARK: - Rows

struct LiveRow {
  let name: String
  let step: LiveStep?
  var problems: [String] = []

  init(name: String, step: StepResult?) {
    self.name = name
    self.step = step.map(LiveStep.init)
  }

  var line: String {
    let status = problems.isEmpty ? "PASS" : "FAIL"
    guard let step else { return "\(status)  \(name): \(problems.joined(separator: "; "))" }
    let timings = [
      ("panel", step.panelShownMs), ("first text", step.firstTextMs), ("done", step.endedMs),
    ].compactMap { label, ms in ms.map { String(format: "%@ %.0f ms", label, $0) } }
    var details =
      [
        "source \(step.source ?? "-")", "\(step.phase ?? "-")",
        "\(step.textUpdates) text updates, \(step.panelStates) panel states",
      ] + timings
    if let result = step.result { details.append("“\(result.prefix(60))”") }
    if let title = step.noticeTitle {
      details.append("“\(title)” “\(step.noticeMessage ?? "")” \(step.noticeActions)")
    }
    let notes = problems.isEmpty ? "" : " — " + problems.joined(separator: "; ")
    return "\(status)  \(name): " + details.joined(separator: ", ") + notes
  }
}

/// The parts of a `read` step's result this driver checks.
struct LiveStep {
  let source: String?
  let captureOK: Bool
  let phase: String?
  let result: String?
  let textUpdates: Int
  let panelStates: Int
  let panelShownMs: Double?
  let firstTextMs: Double?
  let endedMs: Double?
  let escapeSentMs: Double?
  let secondPress: String?
  let callsAfterDismissal: Int
  let visibleAtEnd: Bool
  let noticeTitle: String?
  let noticeMessage: String?
  let noticeActions: [String]
  let note: String?
  let noteAction: String?
  let panelCalls: [String]

  init(_ step: StepResult) {
    let translation = step.translation
    source = step.source
    captureOK = step.ok
    phase = translation["phase"] as? String
    result = translation["result"] as? String
    textUpdates = translation["textUpdates"] as? Int ?? 0
    panelStates = translation["panelStates"] as? Int ?? 0
    panelShownMs = (translation["panelShownMs"] as? NSNumber)?.doubleValue
    firstTextMs = (translation["firstTextMs"] as? NSNumber)?.doubleValue
    endedMs = (translation["endedMs"] as? NSNumber)?.doubleValue
    escapeSentMs = (translation["escapeSentMs"] as? NSNumber)?.doubleValue
    secondPress = translation["secondPress"] as? String
    callsAfterDismissal = translation["callsAfterDismissal"] as? Int ?? 0
    visibleAtEnd = translation["visibleAtEnd"] as? Bool ?? false
    noticeTitle = translation["noticeTitle"] as? String
    noticeMessage = translation["noticeMessage"] as? String
    noticeActions = translation["noticeActions"] as? [String] ?? []
    note = translation["note"] as? String
    noteAction = translation["noteAction"] as? String
    panelCalls = step.panelCalls
  }
}

/// What a `read` step with the model must show.
enum LiveExpectation {
  /// A complete result in `language`, streamed into the panel. `source` nil accepts any path.
  case result(language: NLLanguage, source: String?, secondPress: String? = nil)
  /// The model's error with these buttons.
  case failure(actions: [String], minimumMs: Double = 0)
  /// The stream failed after `text` showed: the text stays, marked incomplete by a note
  /// with this button. Assumes Apple Translation's languages for the pair are not installed,
  /// or it would stand in instead.
  case partial(text: String, noteAction: String)
  /// Ended while streaming by Esc or a second press: hidden, no later panel calls, quickly.
  case cancelled(by: String)

  @MainActor
  func problems(_ result: StepResult) -> [String] {
    let step = LiveStep(result)
    var problems: [String] = []
    guard step.captureOK else { return ["capture failed: \(result.failure ?? "?")"] }
    if step.panelShownMs == nil { problems.append("the panel never showed the translation") }
    switch self {
    case .result(let language, let source, let secondPress):
      if let source, step.source != source {
        problems.append("source \(step.source ?? "-"), expected \(source)")
      }
      if step.phase != "result" { problems.append("ended in \(step.phase ?? "-"), not result") }
      if step.textUpdates < 1 { problems.append("no streamed text") }
      let recognized = step.result.flatMap { NLLanguageRecognizer.dominantLanguage(for: $0) }
      if recognized != language {
        problems.append(
          "result language \(recognized?.rawValue ?? "-"), expected \(language.rawValue)")
      }
      if step.secondPress != secondPress {
        problems.append(
          "second press \(step.secondPress ?? "none"), expected \(secondPress ?? "none")")
      }
      if !step.visibleAtEnd { problems.append("the panel was not visible at the end") }
    case .failure(let actions, let minimumMs):
      if step.phase != "failure" { problems.append("ended in \(step.phase ?? "-"), not failure") }
      if step.noticeActions != actions {
        problems.append("buttons \(step.noticeActions), expected \(actions)")
      }
      if let ended = step.endedMs, ended < minimumMs {
        problems.append(
          String(format: "ended after %.0f ms, expected at least %.0f", ended, minimumMs))
      }
      if !step.visibleAtEnd { problems.append("the panel was not visible at the end") }
    case .partial(let text, let noteAction):
      if step.phase != "partial" { problems.append("ended in \(step.phase ?? "-"), not partial") }
      if step.textUpdates < 1 { problems.append("no streamed text") }
      if step.result != text { problems.append("kept “\(step.result ?? "-")”, expected “\(text)”") }
      if step.note == nil { problems.append("no note under the text") }
      if step.noteAction != noteAction {
        problems.append("note button \(step.noteAction ?? "none"), expected \(noteAction)")
      }
      if !step.visibleAtEnd { problems.append("the panel was not visible at the end") }
    case .cancelled(let by):
      if step.textUpdates == 0 { problems.append("nothing streamed before the cancel") }
      if step.visibleAtEnd { problems.append("the panel was still visible") }
      if step.callsAfterDismissal > 0 {
        problems.append("\(step.callsAfterDismissal) panel calls after the cancel")
      }
      if step.phase != "generating" { problems.append("last state \(step.phase ?? "-")") }
      let sent = by == "escape" ? step.escapeSentMs : (step.secondPress != nil ? 1_200 : nil)
      if by == "press" && step.secondPress != "panel visible" {
        problems.append("second press found the panel \(step.secondPress ?? "never pressed")")
      }
      if let sent, let ended = step.endedMs, ended - sent > 300 {
        problems.append(String(format: "the session ended %.0f ms after the cancel", ended - sent))
      }
    }
    return problems
  }
}
