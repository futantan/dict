// SPDX-License-Identifier: GPL-3.0-or-later
//
// `make matrix` (architecture 14.4, acceptance 15.1 item 3): captures from real apps —
// TextEdit, Safari, the user's Chrome, an isolated cold Chrome and an isolated VS Code —
// through the app's `--e2e` entry point, writes the rows to JSON and compares them with the
// previous run. Web pages come from a local HTTP server and select from their query string.
//
// House rules: each app section holds the UI lock and guards the clipboard; only tabs and
// windows the driver opened are closed (after checking their title); Chrome's
// AXEnhancedUserInterface is restored; isolated instances are killed and their directories
// removed. No AppleScript (it would ask for Automation permission).

import AppKit
import ApplicationServices

struct MatrixRow {
  var app: String
  var control: String
  var state: String
  var ok = false
  var source: String?
  var failure: String?
  var ms: Double?
  var textMatches = false
  var clipboardIntact = false
  var note: String?

  var key: String { "\(app) | \(control) | \(state)" }

  /// The fields compared between runs; timings vary and are only shown.
  var comparable: [String: String] {
    [
      "ok": String(ok), "source": source ?? "-", "failure": failure ?? "-",
      "textMatches": String(textMatches), "clipboardIntact": String(clipboardIntact),
    ]
  }

  var json: [String: Any] {
    var object: [String: Any] = [
      "app": app, "control": control, "state": state, "ok": ok, "textMatches": textMatches,
      "clipboardIntact": clipboardIntact,
    ]
    object["source"] = source ?? NSNull()
    object["failure"] = failure ?? NSNull()
    object["ms"] = ms.map { (($0 * 10).rounded() / 10) as Any } ?? NSNull()
    object["note"] = note ?? NSNull()
    return object
  }

  init(app: String, control: String, state: String) {
    self.app = app
    self.control = control
    self.state = state
  }

  init(json object: [String: Any]) {
    app = object["app"] as? String ?? ""
    control = object["control"] as? String ?? ""
    state = object["state"] as? String ?? ""
    ok = object["ok"] as? Bool ?? false
    source = object["source"] as? String
    failure = object["failure"] as? String
    ms = (object["ms"] as? NSNumber)?.doubleValue
    textMatches = object["textMatches"] as? Bool ?? false
    clipboardIntact = object["clipboardIntact"] as? Bool ?? false
    note = object["note"] as? String
  }

  var line: String {
    let result =
      ok
      ? "\(source ?? "?") \(textMatches ? "text ok" : "TEXT DIFFERS")" : "failure \(failure ?? "?")"
    let timing = ms.map { String(format: "%.1f ms", $0) } ?? "-"
    let clipboard = clipboardIntact ? "clipboard ok" : "CLIPBOARD CHANGED"
    return "\(key): \(result), \(timing), \(clipboard)" + (note.map { " (\($0))" } ?? "")
  }
}

@MainActor
struct Matrix {
  static let port = 8765
  static let sections = ["textedit", "safari", "chrome", "chrome-cold", "vscode"]
  static let webControls = ["web.paragraph", "web.textarea", "web.contenteditable"]
  static let webText = [
    "web.paragraph": "a bright cold day",
    "web.textarea": "five dozen liquor jugs",
    "web.contenteditable": "daft zebras jump",
  ]
  static let sentence = "The quick brown fox jumps over the lazy dog."

  let app: URL
  let pages: URL
  let output: URL
  let work: URL
  let only: [String]?
  private var runner: DictRunner
  private var rows: [MatrixRow] = []

  init(app: URL, pages: URL, output: URL, work: URL, only: [String]?) {
    self.app = app
    self.pages = pages
    self.output = output
    self.work = work
    self.only = only
    runner = DictRunner(app: app, workDirectory: work)
  }

  mutating func run() throws -> Int32 {
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    switch runner.probe() {
    case .finished:
      break
    case .noEntryPoint:
      say(
        "matrix: not implemented: \(app.lastPathComponent) has no --e2e entry point yet (M1.4); "
          + "no apps were opened and \(output.lastPathComponent) was not written")
      return 2
    case .noResult(let reason):
      say("matrix: the --e2e entry point is broken: \(reason)")
      return 1
    }

    try requireUnlockedScreen()
    try startServer()
    for section in only ?? Self.sections {
      guard Self.sections.contains(section) else { throw DriverError("unknown section \(section)") }
      say("matrix: \(section)")
      try UILock.with("make matrix \(section)") {
        try Clipboard.guarded {
          switch section {
          case "textedit": try textEdit()
          case "safari": try safari()
          case "chrome": try chrome()
          case "chrome-cold": try chromeCold()
          default: try vsCode()
          }
        }
      }
    }
    compareAndWrite()
    return 0
  }

  // MARK: Capturing

  private mutating func capture(_ app: String, _ control: String, _ state: String, expect: String) {
    captures(app, control, [state], steps: [Self.captureStep], expect: expect)
  }

  static let captureStep: [String: Any] = ["capture": ["policy": "allowed"]]

  /// Runs `steps` in one Dict process and records a row for each capture step, named by
  /// `states` in order. `during` runs on the driver while Dict runs the steps.
  private mutating func captures(
    _ app: String, _ control: String, _ states: [String], steps: [[String: Any]],
    expect: String, during: () -> Void = {}
  ) {
    let before = Clipboard.hash()
    let outcome = runner.run(
      steps, name: "\(app)-\(control)-\(states.joined(separator: "-"))", during: during)
    let clipboardIntact = Clipboard.hash() == before
    let results: [StepResult]
    var note: String?
    switch outcome {
    case .finished(let steps):
      results = steps.filter { $0.step == "capture" }
      if results.count < states.count { note = "\(results.count) capture steps in the result" }
    case .noEntryPoint:
      results = []
      note = "no --e2e entry point"
    case .noResult(let reason):
      results = []
      note = reason
    }
    for (index, state) in states.enumerated() {
      var row = MatrixRow(app: app, control: control, state: state)
      row.clipboardIntact = clipboardIntact
      row.note = note
      if results.indices.contains(index) {
        let step = results[index]
        row.ok = step.ok
        row.source = step.source
        row.failure = step.failure
        row.ms = step.ms
        row.textMatches = step.ok && step.text == expect
        if step.ok && !row.textMatches { row.note = "got \(E2E.quote(step.text))" }
      }
      say("  " + row.line)
      rows.append(row)
    }
  }

  private mutating func skip(_ app: String, _ reason: String) {
    var row = MatrixRow(app: app, control: "-", state: "-")
    row.note = "skipped: \(reason)"
    say("  " + row.line)
    rows.append(row)
  }

  // MARK: Sections

  private mutating func textEdit() throws {
    let bundleID = "com.apple.TextEdit"
    let wasRunning = !runningPids(bundleID).isEmpty
    let file = work.appendingPathComponent("dict-matrix-textedit.txt")
    try Self.sentence.write(to: file, atomically: true, encoding: .utf8)
    shell(["open", "-a", "TextEdit", file.path])
    guard let pid = poll(timeout: 10, { runningPids(bundleID).first }),
      let window = poll(timeout: 10, { findWindow(pid, titled: "dict-matrix-textedit") })
    else { return skip("TextEdit", "its window did not appear") }
    defer {
      if let close = AX.element(AX.attribute(window, kAXCloseButtonAttribute)) { AX.press(close) }
      if !wasRunning { quit(pid) }
    }
    pause(0.5)
    let target = "quick brown fox"
    guard let text = AX.focusedElement(pid),
      selectRange(text, of: target, in: Self.sentence)
    else { return skip("TextEdit", "could not select text through accessibility") }
    capture("TextEdit", "textView", "warm", expect: target)
  }

  private mutating func safari() throws {
    let bundleID = "com.apple.Safari"
    let wasRunning = !runningPids(bundleID).isEmpty
    for control in Self.webControls {
      guard let pid = openPage(control, in: "Safari", bundleID: bundleID) else {
        skip("Safari", "the page for \(control) did not load")
        continue
      }
      capture("Safari", control, wasRunning ? "warm" : "first", expect: Self.webText[control] ?? "")
      closeTab(pid, control: control)
    }
    if !wasRunning, let pid = runningPids(bundleID).first { quit(pid) }
  }

  /// The user's own Chrome: open test tabs in it, close only those, restore its
  /// AXEnhancedUserInterface value.
  private mutating func chrome() throws {
    let bundleID = "com.google.Chrome"
    guard let pid = runningPids(bundleID).first else {
      return skip("Chrome", "Chrome is not running; the warm rows use the user's own Chrome")
    }
    let attribute = "AXEnhancedUserInterface"
    let original = AX.attribute(AX.app(pid), attribute) as? Bool
    say("  Chrome \(attribute) was \(original.map(String.init) ?? "unset")")
    let restore = Cleanup.add {
      _ = AX.set(AX.app(pid), attribute, (original ?? false) as CFBoolean)
      let now = AX.attribute(AX.app(pid), attribute) as? Bool
      say("  Chrome \(attribute) restored to \(now.map(String.init) ?? "unset")")
    }
    defer { Cleanup.run(restore) }
    for control in Self.webControls {
      guard openPage(control, in: "Google Chrome", bundleID: bundleID) != nil else {
        skip("Chrome", "the page for \(control) did not load")
        continue
      }
      let text = Self.webText[control] ?? ""
      capture("Chrome", control, "first", expect: text)
      pause(2.5)
      capture("Chrome", control, "warm", expect: text)
      closeTab(pid, control: control)
    }
  }

  /// A separate Chrome instance with a throwaway profile: cold on the first capture.
  private mutating func chromeCold() throws {
    let bundleID = "com.google.Chrome"
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("dict-matrix-chrome-\(getpid())")
    let before = Set(runningPids(bundleID))
    let control = "web.textarea"
    shell([
      "open", "-n", "-a", "Google Chrome", "--args", "--user-data-dir=\(directory.path)",
      "--no-first-run", "--no-default-browser-check", "--new-window", pageURL(control),
    ])
    let cleanup = Cleanup.add {
      for pid in Set(runningPids(bundleID)).subtracting(before) { kill(pid, SIGKILL) }
      for pid in pids(matching: directory.path) { kill(pid, SIGKILL) }
      pause(0.5)
      try? FileManager.default.removeItem(at: directory)
    }
    defer { Cleanup.run(cleanup) }
    guard
      let pid = poll(timeout: 15, { Set(runningPids(bundleID)).subtracting(before).first }),
      poll(timeout: 15, { pageIsFront(pid, control: control) ? true : nil }) != nil
    else { return skip("Chrome (isolated)", "the isolated instance did not show the page") }
    pause(0.3)
    let text = Self.webText[control] ?? ""
    capture("Chrome (isolated)", control, "cold", expect: text)
    pause(2.5)
    capture("Chrome (isolated)", control, "warm", expect: text)
  }

  /// An isolated VS Code: throwaway user data and extensions under $TMPDIR (its IPC socket
  /// path must stay under 103 characters), killed with SIGKILL so no crash dialog appears.
  private mutating func vsCode() throws {
    let bundleID = "com.microsoft.VSCode"
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("dvsc\(getpid())")
    let settings = directory.appendingPathComponent("ud/User")
    try FileManager.default.createDirectory(at: settings, withIntermediateDirectories: true)
    try writeJSON(
      [
        "workbench.startupEditor": "none", "security.workspace.trust.enabled": false,
        "telemetry.telemetryLevel": "off", "update.mode": "none", "workbench.tips.enabled": false,
        "extensions.ignoreRecommendations": true, "window.restoreWindows": "none",
      ], to: settings.appendingPathComponent("settings.json"))
    let file = directory.appendingPathComponent("sample.txt")
    try Self.sentence.write(to: file, atomically: true, encoding: .utf8)
    let before = Set(runningPids(bundleID))
    shell([
      "open", "-n", "-a", "Visual Studio Code", "--args", "--user-data-dir",
      directory.appendingPathComponent("ud").path, "--extensions-dir",
      directory.appendingPathComponent("ext").path, "--new-window", "--skip-release-notes",
      "--disable-workspace-trust", file.path,
    ])
    let cleanup = Cleanup.add {
      for pid in Set(runningPids(bundleID)).subtracting(before) { kill(pid, SIGKILL) }
      for pid in pids(matching: directory.path) { kill(pid, SIGKILL) }
      pause(0.5)
      try? FileManager.default.removeItem(at: directory)
    }
    defer { Cleanup.run(cleanup) }
    // Electron support is off until the user agrees (architecture 3.3, 16.1 #1); these rows
    // check the path after they did. The argument domain leaves the saved setting alone.
    runner.extraArguments = ["-AccessibilitySupportElectron", "<true/>"]
    defer { runner.extraArguments = [] }
    guard let pid = poll(timeout: 20, { Set(runningPids(bundleID)).subtracting(before).first }),
      poll(timeout: 30, { AX.focusedWindowTitle(pid)?.contains("sample.txt") == true ? true : nil })
        != nil
    else { return skip("VS Code (isolated)", "its window did not appear") }
    pause(1)
    postKey(pid, keyCode: 0)  // ⌘A
    pause(0.3)
    // Both rows run in one Dict process: Dict keeps the tree on while it runs and turns it off
    // again when it quits, so a second process would find VS Code cold once more.
    captures(
      "VS Code (isolated)", "editor", ["cold", "warm"],
      steps: [Self.captureStep, ["wait": ["ms": 6000]], Self.captureStep], expect: Self.sentence
    ) {
      // Electron loads the text only after Dict's second write (~2.5 s after the first), and
      // that rebuild drops the selection. A ⌘A posted after it did not select (measured), so
      // select again through accessibility once the text is there.
      let loaded = poll(timeout: 5) {
        AX.focusedElement(pid).flatMap { AX.string($0, kAXValueAttribute) } == Self.sentence
          ? true : nil
      }
      let selected = AX.focusedElement(pid).map {
        selectRange($0, of: Self.sentence, in: Self.sentence)
      }
      if loaded == nil || selected != true {
        say("  warning: could not select the VS Code text again before the warm row")
      }
    }
  }

  // MARK: Helpers

  private func pageURL(_ control: String) -> String {
    let text =
      Self.webText[control]?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    return "http://127.0.0.1:\(Self.port)/page.html?control=\(control)&text=\(text)"
  }

  private func pageTitle(_ control: String) -> String { "Dict fixture \(control)" }

  private func pageIsFront(_ pid: pid_t, control: String) -> Bool {
    NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
      && AX.focusedWindowTitle(pid)?.hasPrefix(pageTitle(control)) == true
  }

  /// Opens the page in a new tab of `appName` and waits until it is the front tab.
  private func openPage(_ control: String, in appName: String, bundleID: String) -> pid_t? {
    shell(["open", "-a", appName, pageURL(control)])
    guard let pid = poll(timeout: 10, { runningPids(bundleID).first }),
      poll(timeout: 10, { pageIsFront(pid, control: control) ? true : nil }) != nil
    else { return nil }
    pause(0.3)
    return pid
  }

  /// Closes the front tab with ⌘W, but only when it is the driver's own page.
  private func closeTab(_ pid: pid_t, control: String) {
    guard pageIsFront(pid, control: control) else {
      say("  warning: the front tab is not the test page; left open for you to close")
      return
    }
    postKey(pid, keyCode: 13)  // ⌘W
    pause(0.5)
  }

  private func startServer() throws {
    let server = Process()
    server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    server.arguments = [
      "-m", "http.server", String(Self.port), "--bind", "127.0.0.1", "--directory", pages.path,
    ]
    server.standardOutput = FileHandle.nullDevice
    server.standardError = FileHandle.nullDevice
    try server.run()
    Cleanup.add { server.terminate() }
    let url = "http://127.0.0.1:\(Self.port)/page.html"
    guard
      poll(
        timeout: 10,
        {
          server.isRunning && shell(["curl", "-sf", "-o", "/dev/null", url]).status == 0
            ? true : nil
        }) != nil
    else { throw DriverError("the HTTP server on port \(Self.port) did not start (port in use?)") }
  }

  private mutating func compareAndWrite() {
    let previous = (readJSON(output) as? [String: Any])?["rows"] as? [[String: Any]] ?? []
    let old = Dictionary(
      previous.map { MatrixRow(json: $0) }.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    var differences: [String] = []
    for row in rows {
      guard let before = old[row.key] else {
        differences.append("new: \(row.key)")
        continue
      }
      for (field, value) in row.comparable.sorted(by: { $0.key < $1.key })
      where before.comparable[field] != value {
        differences.append(
          "changed: \(row.key): \(field) \(before.comparable[field] ?? "-") → \(value)")
      }
    }
    let keys = Set(rows.map(\.key))
    differences += old.keys.filter { !keys.contains($0) }.sorted().map { "missing: \($0)" }

    if previous.isEmpty {
      say("matrix: no previous results in \(output.lastPathComponent)")
    } else if differences.isEmpty {
      say("matrix: no differences from the previous run")
    } else {
      say("matrix: differences from the previous run (confirm them by hand):")
      differences.forEach { say("  \($0)") }
    }
    do {
      try writeJSON(["rows": rows.map(\.json)], to: output)
      say("matrix: wrote \(output.path)")
    } catch {
      say("matrix: could not write \(output.path): \(error)")
    }
  }
}

// MARK: - App helpers

@MainActor
func runningPids(_ bundleID: String) -> [pid_t] {
  NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter {
    !$0.isTerminated
  }.map(\.processIdentifier)
}

@MainActor
func findWindow(_ pid: pid_t, titled prefix: String) -> AXUIElement? {
  AX.windows(pid).first { AX.title($0)?.hasPrefix(prefix) == true }
}

@MainActor
func quit(_ pid: pid_t) {
  NSRunningApplication(processIdentifier: pid)?.terminate()
}

/// Selects the first occurrence of `target` in a text element through accessibility.
@MainActor
func selectRange(_ element: AXUIElement, of target: String, in text: String) -> Bool {
  let range = (text as NSString).range(of: target)
  guard range.location != NSNotFound else { return false }
  var cfRange = CFRange(location: range.location, length: range.length)
  guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
  _ = AX.set(element, kAXSelectedTextRangeAttribute, value)
  return poll(timeout: 1) { AX.selectedText(element) == target ? true : nil } != nil
}

/// Posts ⌘<key> to one process (targeted delivery works whatever is frontmost).
@MainActor
func postKey(_ pid: pid_t, keyCode: CGKeyCode) {
  let source = CGEventSource(stateID: .privateState)
  for down in [true, false] {
    let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
    event?.flags = .maskCommand
    event?.postToPid(pid)
  }
}
