// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import Testing

@testable import DictApp

/// A field and clipboard that behave the way the test scripts them. Time moves only through
/// `sleep`, so every timeout runs instantly.
@MainActor
private final class FakeReplaceSystem: ReplaceSystem {
  var frontmost: pid_t? = 42
  /// Until then no app is in front, as right after the panel hides.
  var frontmostFrom: Duration = .zero
  var field: FieldReading?
  var postAllowed = true
  var clipboardDenied = false
  /// What a write of `kAXSelectedText` does to the field, and after how much time.
  var onAXWrite: ((inout FieldReading) -> Void)?
  var axWriteDelay: Duration = .zero
  /// What ⌘V does to the field, and after how much time.
  var onPaste: ((inout FieldReading, String) -> Void)?
  var pasteDelay: Duration = .zero
  /// Something else writes the clipboard while the paste is checked.
  var userCopiesDuringPaste = false

  private(set) var elapsed: Duration = .zero
  private(set) var axWrites = 0
  private(set) var pastes = 0
  private(set) var clipboard = "user's clipboard"
  private(set) var clipboardChangeCount = 1
  private(set) var restores = 0
  private var pending: [(at: Duration, apply: () -> Void)] = []

  func frontmostPID() -> pid_t? { elapsed >= frontmostFrom ? frontmost : nil }

  func read(_ target: ReplaceTarget) async -> FieldReading? { field }

  func writeSelectedText(_ text: String, into target: ReplaceTarget) async {
    axWrites += 1
    guard let onAXWrite else { return }
    schedule(after: axWriteDelay) { self.changeField(onAXWrite) }
  }

  func canPostKeys(to target: ReplaceTarget) -> Bool { postAllowed }

  func snapshotClipboard() -> ClipboardSnapshot {
    ClipboardSnapshot(changeCount: clipboardChangeCount, items: [[(.string, Data(clipboard.utf8))]])
  }

  func writeClipboard(_ text: String) -> Int {
    clipboard = text
    clipboardChangeCount += 1
    return clipboardChangeCount
  }

  func restoreClipboard(_ snapshot: ClipboardSnapshot) {
    restores += 1
    clipboard = String(decoding: snapshot.items[0][0].1, as: UTF8.self)
    clipboardChangeCount += 1
  }

  func postPaste(to pid: pid_t) {
    pastes += 1
    let pasted = clipboard
    if userCopiesDuringPaste {
      clipboard = "copied meanwhile"
      clipboardChangeCount += 1
    }
    guard let onPaste else { return }
    schedule(after: pasteDelay) { self.changeField { onPaste(&$0, pasted) } }
  }

  /// Applies `change` to the field, if there still is one.
  private func changeField(_ change: (inout FieldReading) -> Void) {
    guard var field else { return }
    change(&field)
    self.field = field
  }

  func sleep(_ duration: Duration) async {
    elapsed += duration
    let due = pending.filter { $0.at <= elapsed }
    pending.removeAll { $0.at <= elapsed }
    due.forEach { $0.apply() }
  }

  private func schedule(after delay: Duration, _ apply: @escaping () -> Void) {
    if delay == .zero { apply() } else { pending.append((elapsed + delay, apply)) }
  }
}

/// "I saw teh cat." with "teh" selected.
@MainActor
private func makeTarget(axWritable: Bool = true) -> (ReplaceTarget, FieldReading) {
  let element = AXElement(raw: AXUIElementCreateApplication(42))
  let app = TargetApp(pid: 42, bundleID: "com.example", launchDate: nil, kind: .native)
  let range = CFRange(location: 6, length: 3)
  let target = ReplaceTarget(
    app: app, element: element, range: range, selectedText: "teh", valueBefore: "I saw teh cat.",
    axWritable: axWritable)
  let field = FieldReading(
    isFocused: true, isSecure: false, range: range, selectedText: "teh", value: "I saw teh cat.")
  return (target, field)
}

/// What a text field does when "the" replaces its selection: the caret ends after it.
private func replaceSelection(_ field: inout FieldReading, with text: String) {
  field.value = "I saw \(text) cat."
  field.range = CFRange(location: 6 + text.utf16.count, length: 0)
  field.selectedText = ""
}

@MainActor
struct ReplaceStateMachineTests {
  private func run(
    _ system: FakeReplaceSystem, axWritable: Bool = true
  ) async -> ReplaceOutcome {
    let (target, field) = makeTarget(axWritable: axWritable)
    if system.field == nil { system.field = field }
    return await SystemReplaceWriter(system: system).replace(target, with: "the")
  }

  @Test func anAcceptedAccessibilityWriteNeedsNoPaste() async {
    let system = FakeReplaceSystem()
    system.onAXWrite = { replaceSelection(&$0, with: "the") }
    #expect(await run(system) == .replaced(via: .accessibility))
    #expect(system.pastes == 0)
    #expect(system.clipboard == "user's clipboard")
  }

  /// Chrome, Safari and VS Code report success and change nothing (measured).
  @Test func anIgnoredWriteFallsBackToOnePasteAndRestoresTheClipboard() async {
    let system = FakeReplaceSystem()
    system.onPaste = { replaceSelection(&$0, with: $1) }
    #expect(await run(system) == .replaced(via: .paste))
    #expect(system.axWrites == 1)
    #expect(system.pastes == 1)
    #expect(system.restores == 1)
    #expect(system.clipboard == "user's clipboard")
  }

  @Test func aFieldThatIsNotWritablePastesStraightAway() async {
    let system = FakeReplaceSystem()
    system.onPaste = { replaceSelection(&$0, with: $1) }
    #expect(await run(system, axWritable: false) == .replaced(via: .paste))
    #expect(system.axWrites == 0)
  }

  /// Chromium applies writes asynchronously: one that lands late must not be followed by a
  /// paste, which would insert the result twice.
  @Test func aLateAccessibilityWriteIsWaitedFor() async {
    let system = FakeReplaceSystem()
    system.onAXWrite = { replaceSelection(&$0, with: "the") }
    system.axWriteDelay = .milliseconds(280)
    system.onPaste = { replaceSelection(&$0, with: $1) }
    #expect(await run(system) == .replaced(via: .accessibility))
    #expect(system.pastes == 0)
  }

  @Test func anUnexpectedChangeAfterTheWriteIsReportedWithoutPasting() async {
    let system = FakeReplaceSystem()
    system.onAXWrite = { $0.value = "something else" }
    #expect(await run(system) == .unconfirmed(clipboardHoldsResult: false))
    #expect(system.pastes == 0)
  }

  @Test func aPasteThatNeverLandsFailsAndRestoresTheClipboard() async {
    let system = FakeReplaceSystem()
    #expect(await run(system) == .failed(.pasteNotApplied))
    #expect(system.pastes == 1)
    #expect(system.clipboard == "user's clipboard")
  }

  @Test func aPasteThatLandsLateWithinOneSecondIsConfirmed() async {
    let system = FakeReplaceSystem()
    system.onPaste = { replaceSelection(&$0, with: $1) }
    system.pasteDelay = .milliseconds(600)
    #expect(await run(system) == .replaced(via: .paste))
  }

  /// The app may read the clipboard later; restoring would paste the old content then.
  @Test func anUnexpectedChangeAfterThePasteLeavesTheResultOnTheClipboard() async {
    let system = FakeReplaceSystem()
    system.onPaste = { field, _ in field.value = "I saw the cat.\n" + "the" }
    #expect(await run(system) == .unconfirmed(clipboardHoldsResult: true))
    #expect(system.restores == 0)
    #expect(system.clipboard == "the")
  }

  @Test func aCopyMadeMeanwhileIsNotOverwritten() async {
    let system = FakeReplaceSystem()
    system.onPaste = { replaceSelection(&$0, with: $1) }
    system.userCopiesDuringPaste = true
    #expect(await run(system) == .replaced(via: .paste))
    #expect(system.restores == 0)
    #expect(system.clipboard == "copied meanwhile")
  }

  @Test func withoutPermissionToPostKeysNothingIsPasted() async {
    let system = FakeReplaceSystem()
    system.postAllowed = false
    #expect(await run(system, axWritable: false) == .failed(.noPostEventPermission))
    #expect(system.pastes == 0)
  }

  @Test func aDeniedClipboardIsNotWritten() async {
    let system = FakeReplaceSystem()
    system.clipboardDenied = true
    #expect(await run(system, axWritable: false) == .failed(.clipboardDenied))
    #expect(system.clipboard == "user's clipboard")
  }

  // MARK: Re-checking the target

  @Test func anotherAppInFrontIsStale() async {
    let system = FakeReplaceSystem()
    system.frontmost = 7
    #expect(await run(system) == .stale(.appChanged))
    #expect(system.axWrites == 0)
  }

  enum FieldChange: CaseIterable {
    case unfocused, rangeMoved, otherText, valueEdited, secure

    var reason: StaleReason {
      switch self {
      case .unfocused: .elementChanged
      case .rangeMoved, .otherText: .selectionChanged
      case .valueEdited: .valueChanged
      case .secure: .secureField
      }
    }

    func apply(to field: inout FieldReading) {
      switch self {
      case .unfocused: field.isFocused = false
      case .rangeMoved: field.range = CFRange(location: 0, length: 1)
      case .otherText: field.selectedText = "the"
      case .valueEdited: field.value = "I saw teh cat. More."
      case .secure: field.isSecure = true
      }
    }
  }

  @Test(arguments: FieldChange.allCases)
  func aChangedFieldIsStale(change: FieldChange) async {
    let system = FakeReplaceSystem()
    var field = makeTarget().1
    change.apply(to: &field)
    system.field = field
    #expect(await run(system) == .stale(change.reason))
    #expect(system.axWrites == 0 && system.pastes == 0)
  }

  @Test func anElementThatNoLongerAnswersIsStale() async {
    let system = FakeReplaceSystem()
    let (target, _) = makeTarget()
    system.field = nil
    #expect(
      await SystemReplaceWriter(system: system).replace(target, with: "the")
        == .stale(.elementChanged))
  }

  /// The target app takes key focus back a moment after the panel hides.
  @Test func theCheckWaitsForTheAppToComeBack() async {
    let system = FakeReplaceSystem()
    system.frontmostFrom = .milliseconds(100)
    system.onAXWrite = { replaceSelection(&$0, with: "the") }
    #expect(await run(system) == .replaced(via: .accessibility))
  }

  @Test func theCheckGivesUpAfterThreeHundredMilliseconds() async {
    let system = FakeReplaceSystem()
    system.frontmostFrom = .milliseconds(400)
    #expect(await run(system) == .stale(.appChanged))
  }
}
