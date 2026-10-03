// SPDX-License-Identifier: GPL-3.0-or-later
//
// Self-test of the fixture and the e2e driver, independent of the app's capture code:
//   1. Fixture: every control selects on command (checked through accessibility, which the
//      terminal-run driver may use), the menu bar Copy and Paste items log their events, and
//      bad commands are reported.
//   2. Driver: the e2e run against fake apps passes for a correct one, fails for a wrong one,
//      and skips with "no entry point" (leaving no process behind) for one without `--e2e`.

import AppKit

@MainActor
final class SelfTest {
  private var failures: [String] = []
  private var notes: [String] = []

  private func check(_ condition: Bool, _ message: @autoclosure () -> String) {
    if condition {
      say("  ok    \(message())")
    } else {
      say("  FAIL  \(message())")
      failures.append(message())
    }
  }

  /// Returns true when every check passed.
  func run(fixtureApp: URL, fakes: URL, work: URL) throws -> Bool {
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    say("selftest: fixture")
    if screenIsLocked() {
      check(false, "the screen is unlocked (fixture checks need focus and menu validation)")
    } else {
      try fixtureChecks(fixtureApp: fixtureApp, work: work)
    }
    say("selftest: e2e driver against fake apps")
    try testDriver(fixtureApp: fixtureApp, fakes: fakes, work: work)

    for note in notes { say("note: \(note)") }
    say("selftest: \(failures.isEmpty ? "PASS" : "FAIL (\(failures.count) checks failed)")")
    return failures.isEmpty
  }

  private func fixtureChecks(fixtureApp: URL, work: URL) throws {
    try UILock.with("fixture self-test") {
      try Clipboard.guarded {
        let fixture = Fixture(app: fixtureApp, log: work.appendingPathComponent("fixture.jsonl"))
        try fixture.launch()
        fixture.activate()
        check(fixture.isFrontmost, "the fixture is frontmost after activation")
        testSelection(fixture)
        testMenuCopyAndPaste(fixture)
        testBadCommands(fixture)
      }
    }
  }

  private func testSelection(_ fixture: Fixture) {
    let cases: [(control: String, text: String)] = [
      ("textView.plain", "quick brown fox"),
      ("textView.rich", "black quartz"),
      ("textField", "liquor jugs"),
      ("web.paragraph", "a bright cold day"),
      ("web.paragraph", "lazy dog. It was"),
      ("web.textarea", "five dozen"),
      ("web.contenteditable", "daft zebras"),
    ]
    for (control, text) in cases {
      let detail = fixture.select(control, text)
      check(
        detail == text,
        "\(control): fixture logs select of \"\(text)\" (got \(detail ?? "nothing"))")
      let read = poll(timeout: 1) { () -> String? in
        guard let focused = AX.focusedElement(fixture.pid),
          let selected = AX.selectedText(focused), selected == text
        else { return nil }
        return selected
      }
      check(read == text, "\(control): accessibility reads the selection")
      if control != "web.paragraph", let focused = AX.focusedElement(fixture.pid) {
        let id = AX.identifier(focused)
        check(id == control, "\(control): focused element has identifier \(id ?? "nil")")
      }
    }

    let multi = fixture.select("web.contenteditable", "quartz, judge my vow.\nAnother editable")
    check(
      multi == "quartz, judge my vow.\nAnother editable" || multi?.hasPrefix("quartz") == true,
      "web.contenteditable: selection across paragraphs (\(E2E.quote(multi)))")

    check(fixture.select("secureField", "horse") == "horse", "secureField: fixture logs select")
    let secure = AX.focusedElement(fixture.pid)
    check(
      secure.flatMap { AX.string($0, kAXSubroleAttribute) } == "AXSecureTextField",
      "secureField: focused element is an AXSecureTextField")

    check(
      fixture.select("textView.plain", "beta", content: "Alpha beta gamma.") == "beta",
      "textView.plain: content replaced and selected")
    check(
      AX.focusedElement(fixture.pid).flatMap(AX.selectedText) == "beta",
      "textView.plain: accessibility reads the new selection")
    check(
      fixture.select("web.textarea", "two", content: "one two three") == "two",
      "web.textarea: content replaced and selected")

    check(
      fixture.select("custom.noSelectedText", "big sphinx") == "big sphinx",
      "custom.noSelectedText: fixture logs select")
    let custom = AX.focusedElement(fixture.pid)
    check(
      custom.flatMap(AX.identifier) == "custom.noSelectedText",
      "custom.noSelectedText: is the focused element")
    check(
      custom.map { AX.attribute($0, kAXSelectedTextAttribute) == nil } == true
        && custom.map { AX.attribute($0, kAXValueAttribute) == nil } == true,
      "custom.noSelectedText: exposes neither selected text nor value")
  }

  private func testMenuCopyAndPaste(_ fixture: Fixture) {
    // The selection tests replace some controls' content, so each step sets its own.
    func copyAndExpect(
      _ control: String, _ text: String, content: String? = nil, clipboard: String
    ) {
      let selected = fixture.select(control, text, content: content)
      // A control without selections reports an empty selection (just a caret).
      check(
        selected.map { !$0.hasPrefix("error:") } == true,
        "\(control): placed the selection on \(E2E.quote(text)) (got \(E2E.quote(selected)))")
      let mark = fixture.mark
      guard let copy = AX.menuItem(fixture.pid, key: "C") else {
        return check(false, "menu bar has a ⌘C item")
      }
      check(AX.isEnabled(copy), "\(control): Copy is enabled")
      check(AX.press(copy) == .success, "\(control): Copy pressed")
      let event = poll(timeout: 2) { fixture.entries(since: mark).first { $0.event == "copy" } }
      check(
        event?.control == control,
        "\(control): copy event logged for \(event?.control ?? "nothing")")
      check(
        poll(timeout: 1) { Clipboard.string() == clipboard ? true : nil } == true,
        "\(control): clipboard holds \(E2E.quote(clipboard)) (got \(E2E.quote(Clipboard.string())))"
      )
    }
    copyAndExpect(
      "textView.plain", "lazy dog", content: "The quick brown fox jumps over the lazy dog.",
      clipboard: "lazy dog")
    copyAndExpect("textField", "five dozen", clipboard: "five dozen")
    copyAndExpect(
      "web.textarea", "liquor jugs", content: "Pack my box with five dozen liquor jugs.",
      clipboard: "liquor jugs")
    copyAndExpect("web.paragraph", "quick brown", clipboard: "quick brown")
    copyAndExpect("custom.noSelectedText", "big sphinx", clipboard: "big sphinx")
    copyAndExpect("custom.copiesLine", "let second", clipboard: "let second = 2\n")

    _ = fixture.select("custom.empty", "")
    if let copy = AX.menuItem(fixture.pid, key: "C") {
      let enabled = AX.isEnabled(copy)
      notes.append(
        "custom.empty: the Copy item reads AXEnabled=\(enabled) through accessibility "
          + (enabled ? "(AppKit did not revalidate the menu)" : "(validated on query)"))
    }

    check(
      fixture.select("textView.plain", "lazy dog", content: "The lazy dog.") == "lazy dog",
      "textView.plain: selected \"lazy dog\" for Paste")
    let mark = fixture.mark
    if let paste = AX.menuItem(fixture.pid, key: "V") {
      check(AX.press(paste) == .success, "textView.plain: Paste pressed")
      let event = poll(timeout: 2) { fixture.entries(since: mark).first { $0.event == "paste" } }
      check(event?.control == "textView.plain", "textView.plain: paste event logged")
    } else {
      check(false, "menu bar has a ⌘V item")
    }

    _ = fixture.select("textView.rich", "black quartz")
    let writeMark = fixture.mark
    if let focused = AX.focusedElement(fixture.pid) {
      let error = AX.set(focused, kAXSelectedTextAttribute, "white quartz" as CFString)
      let event = poll(timeout: 1) {
        fixture.entries(since: writeMark).first { $0.event == "axWrite" }
      }
      check(
        error == .success && event?.control == "textView.rich",
        "textView.rich: accessibility write logged (AXError \(error.rawValue))")
    }
  }

  private func testBadCommands(_ fixture: Fixture) {
    check(
      fixture.select("textView.plain", "not in the text")?.hasPrefix("error:") == true,
      "missing text is reported as an error")
    check(
      fixture.select("no.such.control", "x")?.hasPrefix("error: unknown control") == true,
      "unknown control is reported as an error")
    check(
      fixture.select("swiftui.textField", "x")?.hasPrefix("error:") == true,
      "SwiftUI controls (not in M1) are reported as errors")
  }

  private func testDriver(fixtureApp: URL, fakes: URL, work: URL) throws {
    let scenarios = [
      E2EScenario(
        name: "plain text view", control: "textView.plain", text: "quick brown fox",
        policy: "allowed",
        expect: .init(source: "accessibility", text: "quick brown fox", copyEvents: 0)),
      E2EScenario(
        name: "text field", control: "textField", text: "liquor jugs", policy: "allowed",
        expect: .init(source: "accessibility", text: "liquor jugs", copyEvents: 0)),
      E2EScenario(
        name: "web contenteditable", control: "web.contenteditable", text: "daft zebras",
        policy: "never",
        expect: .init(source: "accessibility", text: "daft zebras", copyEvents: 0)),
    ]
    func e2e(_ variant: String) throws -> E2EReport {
      let fake = fakes.appendingPathComponent("FakeDict\(variant).app")
      say("  running the e2e driver with \(fake.lastPathComponent)")
      var e2e = E2E(
        app: fake, fixtureApp: fixtureApp, scenarios: scenarios,
        workDirectory: work.appendingPathComponent("e2e-\(variant)"))
      e2e.needsUnlockedScreen = false
      return try e2e.run()
    }

    let good = try e2e("Echo")
    check(good.passed, "correct fake: all scenarios pass (\(good.summary))")

    let wrong = try e2e("Wrong")
    check(
      wrong.count(.fail) == scenarios.count
        && wrong.outcomes.allSatisfy { $0.notes.contains { $0.hasPrefix("expected text") } },
      "wrong fake: every scenario fails on its text (\(wrong.summary))")

    let none = try e2e("NoEntry")
    check(
      none.count(.skip) == scenarios.count && none.entryPoint.hasPrefix("not implemented"),
      "fake without --e2e: every scenario skipped as not implemented (\(none.summary))")
    let leftover = pids(matching: "FakeDictNoEntry.app")
    check(leftover.isEmpty, "fake without --e2e: no process left behind (\(leftover))")
  }
}
