// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import Testing

@testable import DictApp

/// Suspends a stub until the test opens it.
@MainActor
private final class Gate {
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var isOpen = false

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func open() {
    isOpen = true
    waiters.forEach { $0.resume() }
    waiters = []
  }
}

/// The user's clipboard, for a reader that copies the way the clipboard fallback does.
@MainActor
private final class FakeClipboard {
  var text: String

  init(_ text: String) { self.text = text }
}

/// Answers each capture with the next scripted result, optionally after a gate. With
/// `fallsBack` it reports entering the clipboard fallback first. With a clipboard it acts
/// like the copy fallback: snapshot, copy the selection, wait at the gate for the copy, then
/// restore the snapshot, cancelled or not.
@MainActor
private final class StubReader: SelectionReader {
  var results: [(Result<Selection, CaptureFailure>, Gate?)]
  var fallsBack = false
  var clipboard: FakeClipboard?
  private(set) var calls = 0
  /// Captures that have returned, cancelled or not.
  private(set) var finished = 0

  init(_ results: [(Result<Selection, CaptureFailure>, Gate?)]) { self.results = results }

  func capture(
    policy: ClipboardPolicy, beforeFallback: () -> Void
  ) async -> Result<Selection, CaptureFailure> {
    #expect(policy == .allowed)
    calls += 1
    defer { finished += 1 }
    let (result, gate) = results.removeFirst()
    if fallsBack { beforeFallback() }
    let snapshot = clipboard?.text
    if case .success(let selection) = result { clipboard?.text = selection.text }
    await gate?.wait()
    if let snapshot { clipboard?.text = snapshot }
    return result
  }
}

/// Records what the coordinator asks of the panel.
@MainActor
private final class FakePanel: SessionPanel {
  enum Call: Equatable {
    case show(PanelState, PanelAnchor)
    case update(PanelState)
    case hide
  }

  private(set) var calls: [Call] = []
  private(set) var isVisible = false

  func show(_ state: PanelState, near anchor: PanelAnchor) {
    isVisible = true
    calls.append(.show(state, anchor))
  }

  func update(_ state: PanelState) {
    guard isVisible else { return }
    calls.append(.update(state))
  }

  func hide() {
    isVisible = false
    calls.append(.hide)
  }

  /// The panel closed itself, as on Esc; the controller then calls `onDismiss`.
  func dismissByUser() { isVisible = false }
}

/// Reports scripted states, the last one with `note`, optionally waiting at a gate after the
/// first one.
@MainActor
private final class StubTranslator: SessionTranslator {
  var states: [PanelPhase]
  var gate: Gate?
  var note: PanelNote?
  private(set) var requests: [(text: String, direction: Direction)] = []
  private(set) var sawCancellation = false

  init(_ states: [PanelPhase], gate: Gate? = nil, note: PanelNote? = nil) {
    self.states = states
    self.gate = gate
    self.note = note
  }

  func translate(
    _ text: String, direction: Direction, pair: LanguagePair, update: (PanelState) -> Void
  ) async {
    requests.append((text, direction))
    for (index, phase) in states.enumerated() {
      if index == 1, let gate {
        await gate.wait()
        sawCancellation = Task.isCancelled
      }
      update(
        PanelState(source: text, phase: phase, note: index == states.count - 1 ? note : nil))
    }
  }
}

/// Answers with a scripted proofread, optionally after a gate.
@MainActor
private final class StubProofreader: SessionProofreader {
  var result: Result<AppliedEdits, any Error>
  var gate: Gate?
  private(set) var requests: [String] = []

  init(_ result: Result<AppliedEdits, any Error>) { self.result = result }

  func proofread(_ text: String) async throws -> AppliedEdits {
    requests.append(text)
    await gate?.wait()
    return try result.get()
  }
}

/// Records replacements and answers with a scripted outcome.
@MainActor
private final class StubWriter: ReplaceWriter {
  var outcome = ReplaceOutcome.replaced(via: .accessibility)
  private(set) var writes: [(target: ReplaceTarget, result: String)] = []

  func replace(_ target: ReplaceTarget, with result: String) async -> ReplaceOutcome {
    writes.append((target, result))
    return outcome
  }
}

private let bounds = CGRect(x: 100, y: 500, width: 200, height: 20)
private let mouse = CGPoint(x: 40, y: 60)
private let granted = PermissionStatus(accessibility: true, postEvent: true)
private let app = TargetApp(pid: 42, bundleID: "com.apple.TextEdit", launchDate: nil, kind: .native)

private func selection(
  _ text: String, bounds: CGRect? = bounds, target: ReplaceTarget? = nil,
  context: ContextSentence? = nil
) -> Selection {
  Selection(
    text: text, source: .accessibility, app: app, bounds: bounds, context: context,
    target: target)
}

private func replaceTarget(_ text: String) -> ReplaceTarget {
  ReplaceTarget(
    app: app, element: AXElement(raw: AXUIElementCreateApplication(42)),
    range: CFRange(location: 0, length: text.utf16.count), selectedText: text, valueBefore: text,
    axWritable: true)
}

/// "teh cat" proofread to "the cat".
private let fixed = AppliedEdits(
  text: "the cat", segments: [.changed(from: "teh", to: "the"), .unchanged(" cat")])

@MainActor
private final class Harness {
  let reader: StubReader
  let panel = FakePanel()
  let translator: StubTranslator
  var proofreader: StubProofreader? = StubProofreader(.success(fixed))
  let writer = StubWriter()
  var toasts: [ToastMessage] = []
  var status = granted
  var opened: [String] = []
  var permissionActions: [PanelAction.ID] = []
  /// What the dictionary layer finds for every term.
  var entries: [LexiconEntry] = []
  /// The card model's answer; nil means no model is set up.
  var card: [StreamEvent]?
  /// A fresh log in a temporary folder, never the user's Application Support.
  let vocab: VocabStore? = {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("dict-session-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return try? VocabStore(url: folder.appendingPathComponent("vocab.sqlite"))
  }()
  var spoken: [String] = []
  lazy var coordinator = SessionCoordinator(
    reader: reader, panel: panel,
    environment: SessionCoordinator.Environment(
      makeTranslator: { [unowned self] in translator },
      languagePair: { LanguagePair() },
      refreshPermissions: { [unowned self] in status },
      permissionNotice: {
        PermissionGuide.notice(for: $0, app: .init(name: "Dict", bundleID: "x"))
      },
      performPermissionAction: { [unowned self] in
        permissionActions.append($0)
        return $0.hasPrefix("permissions.")
      },
      openSettings: { [unowned self] in opened.append("settings") },
      mouseLocation: { mouse },
      makeProofreader: { [unowned self] in proofreader },
      replaceWriter: writer,
      showToast: { [unowned self] message, _ in toasts.append(message) },
      lookUpTerm: { [unowned self] _, _ in entries },
      makeCardMaker: { [unowned self] in
        card.map { events in CardMaker(model: ScriptedModel(events: events), makeNonce: { "n" }) }
      },
      vocab: vocab,
      accent: { .american },
      pronounce: { [unowned self] text, language, rate in
        spoken.append("\(text) \(language.minimalIdentifier) \(rate)")
      },
      today: { today }))

  init(
    _ results: [(Result<Selection, CaptureFailure>, Gate?)],
    translator: StubTranslator = StubTranslator([.generating("你"), .result("你好")])
  ) {
    reader = StubReader(results)
    self.translator = translator
  }

  func press(_ role: HotkeyRole = .read) async {
    coordinator.hotkeyPressed(role)
    await coordinator.settle()
  }
}

/// Streams the same scripted events for every request.
private struct ScriptedModel: TextModel {
  let events: [StreamEvent]

  func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, Error> {
    AsyncThrowingStream { continuation in
      for event in events { continuation.yield(event) }
      continuation.finish()
    }
  }
}

private let today = LocalDay(Date(timeIntervalSince1970: 1_791_000_000), in: .gmt)

private func notice(_ issue: PermissionIssue) -> PanelNotice {
  PermissionGuide.notice(for: issue, app: .init(name: "Dict", bundleID: "x"))
}

@MainActor
struct SessionCoordinatorTests {
  @Test func readShowsTheSelectionThenTheTranslation() async {
    let harness = Harness([(.success(selection("Hello there.")), nil)])
    await harness.press()

    #expect(
      harness.panel.calls == [
        .show(PanelState(source: "Hello there.", phase: .generating("")), .selection(bounds)),
        .update(PanelState(source: "Hello there.", phase: .generating("你"))),
        .update(PanelState(source: "Hello there.", phase: .result("你好"))),
      ])
    #expect(harness.translator.requests.map(\.text) == ["Hello there."])
    #expect(harness.translator.requests.map(\.direction) == [.intoMine])
  }

  @Test func withoutBoundsThePanelGoesToTheMouse() async {
    let harness = Harness([(.success(selection("你好吗？", bounds: nil)), nil)])
    await harness.press()

    #expect(
      harness.panel.calls.first
        == .show(PanelState(source: "你好吗？", phase: .generating("")), .mouse(mouse)))
    #expect(harness.translator.requests.map(\.direction) == [.intoLearning])
  }

  @Test func nothingSelectedOpensTheInputThenTranslatesTypedText() async {
    let harness = Harness([(.failure(.nothingSelected(fieldText: nil)), nil)])
    await harness.press()
    #expect(harness.panel.calls == [.show(.input, .mouse(mouse))])

    harness.coordinator.submitted("Bonjour à tous.")
    await harness.coordinator.settle()

    #expect(harness.translator.requests.map(\.text) == ["Bonjour à tous."])
    #expect(
      harness.panel.calls.dropFirst().first
        == .update(PanelState(source: "Bonjour à tous.", phase: .generating(""))))
    #expect(
      harness.panel.calls.last
        == .update(PanelState(source: "Bonjour à tous.", phase: .result("你好"))))
  }

  @Test func blankSelectionCountsAsNothingSelected() async {
    let harness = Harness([(.success(selection("  \n ")), nil)])
    await harness.press()

    #expect(harness.panel.calls == [.show(.input, .mouse(mouse))])
    #expect(harness.translator.requests.isEmpty)
  }

  @Test func missingPermissionShowsTheGuide() async {
    let harness = Harness([(.failure(.noAccessibilityPermission), nil)])
    harness.status = PermissionStatus(accessibility: false, postEvent: false)
    await harness.press()

    #expect(
      harness.panel.calls == [
        .show(PanelState(phase: .needsSetup(notice(.missing(.accessibility)))), .mouse(mouse))
      ])
    #expect(harness.translator.requests.isEmpty)
  }

  /// Trusted, yet accessibility fails: the grant belongs to an older signature.
  @Test func trustedButFailingIsAStaleGrant() async {
    let harness = Harness([(.failure(.noAccessibilityPermission), nil)])
    await harness.press()

    #expect(
      harness.panel.calls == [
        .show(PanelState(phase: .needsSetup(notice(.staleAccessibility))), .mouse(mouse))
      ])
  }

  @Test func grantWhileTheGuideIsShownReadsAgain() async {
    let harness = Harness([
      (.failure(.noAccessibilityPermission), nil), (.success(selection("Hello there.")), nil),
    ])
    harness.status = PermissionStatus(accessibility: false, postEvent: true)
    await harness.press()

    harness.status = granted
    harness.coordinator.permissionsChanged(granted: [.accessibility])
    await harness.coordinator.settle()

    #expect(harness.reader.calls == 2)
    #expect(harness.panel.calls[1] == .hide)
    #expect(
      harness.panel.calls.last == .update(PanelState(source: "Hello there.", phase: .result("你好"))))
  }

  @Test func grantWithoutAWaitingSessionDoesNothing() async {
    let harness = Harness([(.success(selection("Hello there.")), nil)])
    await harness.press()
    let calls = harness.panel.calls

    harness.coordinator.permissionsChanged(granted: [.accessibility])
    await harness.coordinator.settle()

    #expect(harness.reader.calls == 1)
    #expect(harness.panel.calls == calls)
  }

  @Test func otherCaptureFailuresAreExplained() async {
    let harness = Harness([(.failure(.secureField), nil)])
    await harness.press()

    #expect(
      harness.panel.calls == [
        .show(
          PanelState(phase: .failure(SessionStrings.captureFailure(.secureField))), .mouse(mouse))
      ])
  }

  @Test func ownAppShowsNothing() async {
    let harness = Harness([(.failure(.ownApp), nil)])
    await harness.press()

    #expect(harness.panel.calls.isEmpty)
  }

  /// A second press while the first capture still waits for its copy would start a second
  /// capture that snapshots the copied selection as "the user's clipboard" and restores it
  /// last, leaving the selection on the clipboard. Presses before the panel shows are
  /// ignored instead.
  @Test func aPressWhileCapturingIsIgnored() async {
    let copied = Gate()
    let harness = Harness([
      (.success(selection("First")), copied), (.success(selection("Second")), copied),
    ])
    let clipboard = FakeClipboard("the user's clipboard")
    harness.reader.clipboard = clipboard

    harness.coordinator.hotkeyPressed(.read)
    for _ in 0..<5 { await Task.yield() }
    harness.coordinator.hotkeyPressed(.read)
    for _ in 0..<5 { await Task.yield() }
    copied.open()
    await harness.coordinator.settle()
    for _ in 0..<10 { await Task.yield() }

    #expect(clipboard.text == "the user's clipboard")
    #expect(harness.reader.calls == 1)
    #expect(harness.translator.requests.map(\.text) == ["First"])
  }

  /// Once the capture is over, presses work again.
  @Test func aPressAfterTheCaptureEndedIsHandled() async {
    let harness = Harness([(.failure(.ownApp), nil), (.success(selection("Hello there.")), nil)])
    await harness.press()
    await harness.press()

    #expect(harness.reader.calls == 2)
    #expect(harness.translator.requests.map(\.text) == ["Hello there."])
  }

  // MARK: The reading panel before the clipboard fallback (architecture 11.1)

  /// The first stage read the text: no reading panel, straight to the selection.
  @Test func firstStageSuccessShowsNoReadingPanel() async {
    let harness = Harness([(.success(selection("Hello there.")), nil)])
    await harness.press()

    #expect(!harness.panel.calls.contains(.show(PanelState(phase: .reading), .mouse(mouse))))
    #expect(
      harness.panel.calls.first
        == .show(PanelState(source: "Hello there.", phase: .generating("")), .selection(bounds)))
  }

  /// The panel shows "reading" at the mouse before the fallback copies anything, and the
  /// result then replaces it in place instead of showing the panel again.
  @Test func fallbackShowsReadingFirstThenUpdatesInPlace() async {
    let copied = Gate()
    let harness = Harness([(.success(selection("Hello there.", bounds: nil)), copied)])
    harness.reader.fallsBack = true

    harness.coordinator.hotkeyPressed(.read)
    for _ in 0..<5 { await Task.yield() }
    #expect(harness.panel.calls == [.show(PanelState(phase: .reading), .mouse(mouse))])
    #expect(harness.panel.isVisible)

    copied.open()
    await harness.coordinator.settle()
    #expect(
      harness.panel.calls == [
        .show(PanelState(phase: .reading), .mouse(mouse)),
        .update(PanelState(source: "Hello there.", phase: .generating(""))),
        .update(PanelState(source: "Hello there.", phase: .generating("你"))),
        .update(PanelState(source: "Hello there.", phase: .result("你好"))),
      ])
    #expect(harness.translator.requests.map(\.text) == ["Hello there."])
  }

  @Test func fallbackFailureReplacesTheReadingPanel() async {
    let harness = Harness([(.failure(.unreadable(axError: -25212)), nil)])
    harness.reader.fallsBack = true
    await harness.press()

    #expect(
      harness.panel.calls == [
        .show(PanelState(phase: .reading), .mouse(mouse)),
        .update(
          PanelState(
            phase: .failure(SessionStrings.captureFailure(.unreadable(axError: -25212))))),
      ])
  }

  @Test func fallbackWithNothingSelectedTurnsIntoTheInput() async {
    let harness = Harness([(.failure(.nothingSelected(fieldText: nil)), nil)])
    harness.reader.fallsBack = true
    await harness.press()

    #expect(
      harness.panel.calls == [.show(PanelState(phase: .reading), .mouse(mouse)), .update(.input)])
  }

  /// The shortcut hides the reading panel; the capture still puts the clipboard back, nothing
  /// is translated, and presses are ignored until that capture has wound down.
  @Test func theShortcutDuringTheFallbackHidesAndCancels() async {
    let copied = Gate()
    let harness = Harness([
      (.success(selection("Hello there.", bounds: nil)), copied),
      (.success(selection("Next")), nil),
    ])
    harness.reader.fallsBack = true
    let clipboard = FakeClipboard("the user's clipboard")
    harness.reader.clipboard = clipboard

    harness.coordinator.hotkeyPressed(.read)
    for _ in 0..<5 { await Task.yield() }
    harness.coordinator.hotkeyPressed(.read)
    #expect(harness.panel.calls.last == .hide)
    harness.coordinator.hotkeyPressed(.read)
    #expect(harness.reader.calls == 1)

    copied.open()
    await harness.coordinator.settle()
    for _ in 0..<10 { await Task.yield() }

    #expect(harness.reader.finished == 1)
    #expect(clipboard.text == "the user's clipboard")
    #expect(harness.translator.requests.isEmpty)
    #expect(
      harness.panel.calls == [.show(PanelState(phase: .reading), .mouse(mouse)), .hide])

    await harness.press()
    #expect(harness.reader.calls == 2)
  }

  /// Esc on the reading panel ends the session the same way.
  @Test func dismissingTheReadingPanelCancelsTheCapture() async {
    let copied = Gate()
    let harness = Harness([(.success(selection("Hello there.", bounds: nil)), copied)])
    harness.reader.fallsBack = true
    let clipboard = FakeClipboard("the user's clipboard")
    harness.reader.clipboard = clipboard

    harness.coordinator.hotkeyPressed(.read)
    for _ in 0..<5 { await Task.yield() }
    harness.panel.dismissByUser()
    harness.coordinator.panelDismissed(.escape)
    copied.open()
    await harness.coordinator.settle()

    #expect(clipboard.text == "the user's clipboard")
    #expect(harness.translator.requests.isEmpty)
    #expect(harness.panel.calls == [.show(PanelState(phase: .reading), .mouse(mouse))])
  }

  @Test func theSameKeyWhileShownHidesAndCancels() async {
    let gate = Gate()
    let translator = StubTranslator([.generating("你"), .result("你好")], gate: gate)
    let harness = Harness([(.success(selection("Hello there.")), nil)], translator: translator)
    harness.coordinator.hotkeyPressed(.read)
    for _ in 0..<5 { await Task.yield() }
    #expect(harness.panel.isVisible)

    harness.coordinator.hotkeyPressed(.read)
    gate.open()
    await harness.coordinator.settle()

    #expect(harness.reader.calls == 1)
    #expect(harness.panel.calls.last == .hide)
    #expect(translator.sawCancellation)
    #expect(
      !harness.panel.calls.contains(
        .update(PanelState(source: "Hello there.", phase: .result("你好")))))
  }

  @Test func dismissingThePanelCancelsTheTranslation() async {
    let gate = Gate()
    let translator = StubTranslator([.generating("你"), .result("你好")], gate: gate)
    let harness = Harness([(.success(selection("Hello there.")), nil)], translator: translator)
    harness.coordinator.hotkeyPressed(.read)
    for _ in 0..<5 { await Task.yield() }

    harness.panel.dismissByUser()
    harness.coordinator.panelDismissed(.escape)
    gate.open()
    await harness.coordinator.settle()

    #expect(translator.sawCancellation)
    #expect(
      !harness.panel.calls.contains(
        .update(PanelState(source: "Hello there.", phase: .result("你好")))))
  }

  @Test func aFinishedTranslationIsRecorded() async throws {
    let harness = Harness([(.success(selection("Hello there.")), nil)])
    await harness.press()

    let sentences = try await harness.vocab?.day(today).sentences
    #expect(sentences?.map(\.kind) == [.translated])
    #expect(sentences?.first?.source == "Hello there.")
    #expect(sentences?.first?.result == "你好")
    #expect(sentences?.first?.sourceLanguage == "en")
    #expect(sentences?.first?.resultLanguage == "zh")
  }

  @Test func translationFailuresAreShownAsReported() async {
    let failure = PanelNotice(title: "The model couldn’t translate this")
    let harness = Harness(
      [(.success(selection("Hello there.")), nil)],
      translator: StubTranslator([.generating(""), .failure(failure)]))
    await harness.press()

    #expect(
      harness.panel.calls.last
        == .update(PanelState(source: "Hello there.", phase: .failure(failure))))
  }

  /// The incomplete text stays in the panel, and its note's "Try Again" translates again.
  @Test func incompleteTranslationStaysAndRetries() async {
    let note = PanelNote(
      "incomplete", action: PanelAction(id: TranslationStrings.retryAction, title: "Try Again"))
    let incomplete = PanelState(source: "Hello there.", phase: .partial("你好"), note: note)
    let harness = Harness(
      [(.success(selection("Hello there.")), nil)],
      translator: StubTranslator([.generating("你好"), .partial("你好")], note: note))
    await harness.press()
    #expect(harness.panel.calls.last == .update(incomplete))

    harness.coordinator.perform(TranslationStrings.retryAction)
    await harness.coordinator.settle()
    #expect(harness.translator.requests.map(\.text) == ["Hello there.", "Hello there."])
    #expect(harness.panel.calls.last == .update(incomplete))
  }

  @Test func retryTranslatesTheSameTextAgain() async {
    let harness = Harness([(.success(selection("Hello there.")), nil)])
    await harness.press()

    harness.coordinator.perform(TranslationStrings.retryAction)
    await harness.coordinator.settle()

    #expect(harness.reader.calls == 1)
    #expect(harness.translator.requests.map(\.text) == ["Hello there.", "Hello there."])
  }

  @Test func openSettingsEndsTheSession() async {
    let harness = Harness([(.success(selection("Hello there.")), nil)])
    await harness.press()
    harness.coordinator.perform(TranslationStrings.openSettingsAction)

    #expect(harness.panel.calls.last == .hide)
    #expect(harness.opened == ["settings"])
    #expect(!harness.panel.isVisible)
  }

  /// The onboarding sample goes straight to the panel and the translator, without a capture.
  @Test func sampleIsTranslatedWithoutReading() async {
    let harness = Harness([])
    let anchor = PanelAnchor.selection(CGRect(x: 10, y: 20, width: 300, height: 40))
    harness.coordinator.translateSample("Hello there.", near: anchor)
    await harness.coordinator.settle()

    #expect(harness.reader.calls == 0)
    #expect(
      harness.panel.calls == [
        .show(PanelState(source: "Hello there.", phase: .generating("")), anchor),
        .update(PanelState(source: "Hello there.", phase: .generating("你"))),
        .update(PanelState(source: "Hello there.", phase: .result("你好"))),
      ])
  }

  @Test func permissionActionsGoToTheGuide() async {
    let harness = Harness([(.failure(.noAccessibilityPermission), nil)])
    harness.status = PermissionStatus(accessibility: false, postEvent: false)
    await harness.press()

    harness.coordinator.perform(PermissionGuide.ActionID.openSettings)

    #expect(harness.permissionActions == [PermissionGuide.ActionID.openSettings])
  }
}

@MainActor
struct WriteSessionTests {
  @Test func writeChecksTheSelectionThenShowsTheDiff() async {
    let target = replaceTarget("teh cat")
    let harness = Harness([(.success(selection("teh cat", target: target)), nil)])
    await harness.press(.write)

    #expect(
      harness.panel.calls == [
        .show(PanelState(phase: .checking("teh cat")), .selection(bounds)),
        .update(PanelState(phase: .corrected(Correction(fixed, replaceable: true)))),
      ])
    #expect(harness.proofreader?.requests == ["teh cat"])
    #expect(harness.translator.requests.isEmpty)
  }

  @Test func withoutAFieldToWriteTheDiffCanOnlyBeCopied() async {
    let harness = Harness([(.success(selection("teh cat")), nil)])
    await harness.press(.write)

    #expect(
      harness.panel.calls.last
        == .update(PanelState(phase: .corrected(Correction(fixed, replaceable: false)))))
    harness.coordinator.confirm()
    await harness.coordinator.settle()
    #expect(harness.writer.writes.isEmpty)
    #expect(harness.panel.isVisible)
  }

  @Test func returnHidesThePanelThenReplacesAndReports() async {
    let target = replaceTarget("teh cat")
    let harness = Harness([(.success(selection("teh cat", target: target)), nil)])
    await harness.press(.write)

    harness.coordinator.confirm()
    await harness.coordinator.settle()

    #expect(harness.panel.calls.last == .hide)
    #expect(harness.writer.writes.map(\.result) == ["the cat"])
    #expect(harness.writer.writes.first?.target.selectedText == "teh cat")
    #expect(harness.toasts == [.replaced])
    let sentences = try? await harness.vocab?.day(today).sentences
    #expect(sentences?.map(\.kind) == [.corrected])
    #expect(sentences?.first?.source == "teh cat")
    #expect(sentences?.first?.result == "the cat")
    #expect(sentences?.first?.applied == true)
    #expect(sentences?.first?.editsJSON == #"[{"right":"the","wrong":"teh"}]"#)
    #expect(sentences?.first?.sourceApp == "com.apple.TextEdit")
  }

  @Test func aStaleTargetIsReportedWithTheResultToCopy() async {
    let harness = Harness([(.success(selection("teh cat", target: replaceTarget("teh cat"))), nil)])
    harness.writer.outcome = .stale(.valueChanged)
    await harness.press(.write)
    harness.coordinator.confirm()
    await harness.coordinator.settle()

    #expect(harness.toasts == [.notReplaced(result: "the cat")])
  }

  @Test func withoutAModelTheSettingsAreOffered() async {
    let harness = Harness([(.success(selection("teh cat")), nil)])
    harness.proofreader = nil
    await harness.press(.write)

    #expect(
      harness.panel.calls.last == .update(PanelState(phase: .needsSetup(WritingStrings.needsModel)))
    )
  }

  @Test func nothingSelectedAsksForASelection() async {
    let harness = Harness([(.failure(.nothingSelected(fieldText: nil)), nil)])
    await harness.press(.write)

    #expect(
      harness.panel.calls == [
        .show(PanelState(phase: .failure(WritingStrings.nothingToCheck)), .mouse(mouse))
      ])
  }

  @Test func theWriteKeyHidesAVisiblePanel() async {
    let gate = Gate()
    let harness = Harness([(.success(selection("teh cat")), nil)])
    harness.proofreader?.gate = gate
    harness.coordinator.hotkeyPressed(.write)
    for _ in 0..<5 { await Task.yield() }
    #expect(harness.panel.isVisible)

    harness.coordinator.hotkeyPressed(.write)
    gate.open()
    await harness.coordinator.settle()
    #expect(!harness.panel.isVisible)
    #expect(harness.panel.calls.last == .hide)
  }
}

// MARK: - Looking up words

private let runEntry = LexiconEntry(
  lemma: "run", ipaUS: "/ɹʌn/", ipaUK: "/rʌn/", band: .common,
  senses: [
    LexiconSense(pos: "verb", gloss: "跑、奔跑、走", source: "en"),
    LexiconSense(pos: "verb", gloss: "经营、管理", source: "en"),
  ])

private let ranCard = WordCard(
  status: .ok, lemma: "run", phonetic: "/rʌn/", partOfSpeech: "verb", definition: "经营；管理",
  contextTranslation: "她经营一家小面包店。",
  otherSenses: [WordCard.Sense(partOfSpeech: "verb", definition: "跑；奔跑")],
  examples: [WordCard.Example(sentence: "Who runs this shop?", translation: "这家店谁在经营？")],
  collocations: [WordCard.Collocation(phrase: "run a business", meaning: "经营生意")],
  level: "B1")

/// `ranCard` as a strict model writes it, in the schema's key order.
private let ranJSON = """
  {"status":"ok","lemma":"run","phonetic":"/rʌn/","partOfSpeech":"verb",\
  "definition":"经营；管理","contextTranslation":"她经营一家小面包店。",\
  "otherSenses":[{"partOfSpeech":"verb","definition":"跑；奔跑"}],\
  "examples":[{"sentence":"Who runs this shop?","translation":"这家店谁在经营？"}],\
  "collocations":[{"phrase":"run a business","meaning":"经营生意"}],"level":"B1"}
  """

/// The answer cut where a stream would cut it, so the short fields arrive before the end.
private let ranStream: [StreamEvent] =
  stride(from: 0, to: ranJSON.count, by: 9).map { start in
    let from = ranJSON.index(ranJSON.startIndex, offsetBy: start)
    let to = ranJSON.index(from, offsetBy: 9, limitedBy: ranJSON.endIndex) ?? ranJSON.endIndex
    return StreamEvent.text(String(ranJSON[from..<to]))
  } + [.finished(.complete, nil)]

private let bakery = "She ran a small bakery."

private func context(_ term: String, in sentence: String) -> ContextSentence? {
  sentence.range(of: term).map { ContextSentence(sentence: sentence, termRange: $0) }
}

private func ran() -> Selection {
  selection("ran", context: context("ran", in: bakery))
}

extension FakePanel {
  /// The card in the last call, if it shows one.
  fileprivate var lastCard: CardState? {
    guard let call = calls.last else { return nil }
    switch call {
    case .show(let state, _), .update(let state):
      if case .card(let card) = state.phase { return card }
      return nil
    case .hide:
      return nil
    }
  }

  fileprivate var lastState: PanelState? {
    switch calls.last {
    case .show(let state, _), .update(let state): state
    default: nil
    }
  }
}

@MainActor
struct SessionLookupTests {
  @Test func aWordShowsTheDictionaryLayerThenTheModelCard() async throws {
    let harness = Harness([(.success(ran()), nil)])
    harness.entries = [runEntry]
    harness.card = ranStream
    await harness.press()

    let first = CardState(
      term: "ran", context: bakery, entry: runEntry, accent: .american, model: .loading)
    #expect(harness.panel.calls.first == .show(PanelState(phase: .card(first)), .selection(bounds)))
    // The count arrives before any of the model's fields.
    var counted = first
    counted.encounters = 1
    #expect(harness.panel.calls[1] == .update(PanelState(phase: .card(counted))))
    var streamed = counted
    streamed.show(definition: "经营；管理", contextTranslation: nil)
    #expect(harness.panel.calls.contains(.update(PanelState(phase: .card(streamed)))))
    var complete = counted
    complete.show(ranCard)
    #expect(harness.panel.lastState == PanelState(phase: .card(complete)))
    #expect(harness.translator.requests.isEmpty)

    let log = try #require(try await harness.vocab?.day(today))
    #expect(log.lookups.map(\.term.lemma) == ["run"])
    let encounter = try #require(log.lookups.first?.encounter)
    #expect(encounter.surface == "ran")
    #expect(encounter.sentence == bakery)
    #expect(encounter.termStart == 4)
    #expect(encounter.termLength == 3)
    #expect(encounter.source == .accessibility)
    #expect(encounter.sourceApp == "com.apple.TextEdit")
  }

  @Test func theSecondLookupShowsTheCount() async {
    let harness = Harness([(.success(ran()), nil), (.success(selection("runs")), nil)])
    harness.entries = [runEntry]
    harness.card = ranStream
    await harness.press()
    #expect(harness.panel.lastCard?.shownEncounters == nil)
    harness.coordinator.end()

    await harness.press()
    #expect(harness.panel.lastCard?.shownEncounters == 2)
  }

  @Test func withoutAModelTheDictionaryLayerSaysWhatIsMissing() async {
    let harness = Harness([(.success(ran()), nil)])
    harness.entries = [runEntry]
    await harness.press()

    var card = CardState(
      term: "ran", context: bakery, entry: runEntry, accent: .american, model: .unavailable)
    card.encounters = 1
    #expect(
      harness.panel.lastState == PanelState(phase: .card(card), note: CardStrings.needsModelNote))
  }

  @Test func withNeitherDictionaryNorModelTheWordIsTranslated() async throws {
    // Looking it up again could only translate it again, so it is not offered.
    let harness = Harness([(.success(ran()), nil)])
    await harness.press()

    #expect(harness.translator.requests.map(\.text) == ["ran"])
    #expect(
      harness.panel.calls.first
        == .show(
          PanelState(source: "ran", phase: .generating(""), offersLookUp: false),
          .selection(bounds)))
    #expect(
      harness.panel.lastState
        == PanelState(source: "ran", phase: .result("你好"), offersLookUp: false))
    // Nothing says it is a word, so it is not recorded as one.
    #expect(try await harness.vocab?.day(today).lookups.isEmpty == true)
  }

  @Test func withoutTheDictionaryTheModelCardIsRecordedOnceItIsATerm() async throws {
    let harness = Harness([(.success(ran()), nil)])
    harness.card = ranStream
    await harness.press()

    #expect(harness.panel.lastCard?.lemma == "run")
    #expect(harness.panel.lastCard?.encounters == 1)
    let log = try #require(try await harness.vocab?.day(today))
    // Keyed by the text as selected, never by the model's lemma (architecture 8.1).
    #expect(log.lookups.map(\.term.lemmaKey) == ["ran"])
  }

  @Test func notATermIsTranslatedInstead() async throws {
    let json = """
      {"status":"not_a_term","lemma":"","phonetic":"","partOfSpeech":"","definition":"",\
      "contextTranslation":"","otherSenses":[],"examples":[],"collocations":[],"level":""}
      """
    let harness = Harness([(.success(selection("asdfgh")), nil)])
    harness.card = [.text(json), .finished(.complete, nil)]
    await harness.press()

    #expect(harness.translator.requests.map(\.text) == ["asdfgh"])
    #expect(harness.panel.lastState?.phase == .result("你好"))
    #expect(try await harness.vocab?.day(today).lookups.isEmpty == true)
  }

  @Test func aFailedModelKeepsTheDictionaryLayer() async {
    let harness = Harness([(.success(ran()), nil)])
    harness.entries = [runEntry]
    harness.card = [.text(#"{"status":"ok","#)]
    await harness.press()

    #expect(harness.panel.lastCard?.model == .unavailable)
    #expect(harness.panel.lastCard?.senses.count == 2)
    #expect(harness.panel.lastState?.note == CardStrings.failureNote(CardStreamError.interrupted))

    // Try Again asks again for the same lookup without counting it twice.
    harness.card = ranStream
    harness.coordinator.perform(TranslationStrings.retryAction)
    await harness.coordinator.settle()
    #expect(harness.panel.lastCard?.model == .complete)
    #expect(harness.panel.lastCard?.encounters == 1)
  }

  @Test func learnMarksTheWordAndAgainUnmarksIt() async throws {
    let harness = Harness([(.success(ran()), nil)])
    harness.entries = [runEntry]
    await harness.press()

    harness.coordinator.perform(CardStrings.learnAction)
    await harness.coordinator.settle()
    #expect(harness.panel.lastCard?.isLearning == true)
    let learning = try await harness.vocab?.term(language: "en", lemmaKey: "run")
    #expect(learning?.tier == .learning)

    harness.coordinator.perform(CardStrings.learnAction)
    await harness.coordinator.settle()
    #expect(harness.panel.lastCard?.isLearning == false)
    let seen = try await harness.vocab?.term(language: "en", lemmaKey: "run")
    #expect(seen?.tier == .seen)
  }

  @Test func pronounceSaysTheLemmaThenSlowly() async {
    let harness = Harness([(.success(ran()), nil)])
    harness.entries = [runEntry]
    await harness.press()

    harness.coordinator.perform(CardStrings.pronounceAction)
    harness.coordinator.perform(CardStrings.pronounceAction)
    harness.coordinator.perform(CardStrings.pronounceAction)
    #expect(harness.spoken == ["run en normal", "run en slow", "run en normal"])
  }

  @Test func cardActionsNeedACard() async {
    let harness = Harness([(.success(selection("Hello there.")), nil)])
    await harness.press()
    let calls = harness.panel.calls

    harness.coordinator.perform(CardStrings.pronounceAction)
    harness.coordinator.perform(CardStrings.learnAction)
    harness.coordinator.perform(CardStrings.translateAction)
    harness.coordinator.perform(CardStrings.lookUpAction)
    await harness.coordinator.settle()
    #expect(harness.spoken.isEmpty)
    #expect(harness.panel.calls == calls)
  }

  @Test func theCardTurnsIntoTheTranslationAndBack() async throws {
    let harness = Harness([(.success(ran()), nil)])
    harness.entries = [runEntry]
    harness.card = ranStream
    await harness.press()

    harness.coordinator.perform(CardStrings.translateAction)
    await harness.coordinator.settle()
    #expect(harness.translator.requests.map(\.text) == ["ran"])
    #expect(
      harness.panel.lastState
        == PanelState(source: "ran", phase: .result("你好"), offersLookUp: true))

    harness.coordinator.perform(CardStrings.lookUpAction)
    await harness.coordinator.settle()
    #expect(harness.panel.lastCard?.model == .complete)
    #expect(harness.panel.lastCard?.context == bakery)
    // The same lookup shown again, not a second one.
    #expect(harness.panel.lastCard?.encounters == 1)
    let log = try #require(try await harness.vocab?.day(today))
    #expect(log.lookups.count == 1)
    // A word translated is not a sentence event; only a passage is (architecture 8.1).
    #expect(log.sentences.isEmpty)
  }

  /// The on-screen sequence of the M2 check: a second lookup, ⌘S twice, then Translate and
  /// Look Up. Neither switch is a new lookup.
  @Test func switchingAfterASecondLookupKeepsTheCount() async throws {
    let harness = Harness([(.success(ran()), nil), (.success(ran()), nil)])
    harness.entries = [runEntry]
    harness.card = ranStream
    await harness.press()
    harness.coordinator.end()
    await harness.press()
    #expect(harness.panel.lastCard?.shownEncounters == 2)

    harness.coordinator.perform(CardStrings.learnAction)
    await harness.coordinator.settle()
    harness.coordinator.perform(CardStrings.learnAction)
    await harness.coordinator.settle()
    harness.coordinator.perform(CardStrings.translateAction)
    await harness.coordinator.settle()
    harness.coordinator.perform(CardStrings.lookUpAction)
    await harness.coordinator.settle()
    harness.coordinator.perform(CardStrings.translateAction)
    await harness.coordinator.settle()
    harness.coordinator.perform(CardStrings.lookUpAction)
    await harness.coordinator.settle()

    #expect(harness.panel.lastCard?.shownEncounters == 2)
    let log = try #require(try await harness.vocab?.day(today))
    #expect(log.lookups.count == 2)
    #expect(log.sentences.isEmpty)
    let term = try await harness.vocab?.term(language: "en", lemmaKey: "run")
    #expect(term?.tier == .seen)
  }

  @Test func aTranslatedPhraseIsNotASentenceEvent() async throws {
    let harness = Harness([(.success(selection("take off")), nil)])
    await harness.press()

    #expect(harness.panel.lastState?.phase == .result("你好"))
    #expect(try await harness.vocab?.day(today).sentences.isEmpty == true)
  }

  @Test func aPassageOffersNoLookUp() async {
    let harness = Harness([(.success(selection("Hello there.")), nil)])
    await harness.press()
    #expect(harness.panel.lastState?.offersLookUp == false)
  }

  @Test func nothingToLookUpSendsNoRequest() async {
    let harness = Harness([(.success(selection("https://example.com")), nil)])
    harness.card = ranStream
    await harness.press()

    #expect(
      harness.panel.calls == [
        .show(PanelState(phase: .failure(CardStrings.nothingToLookUp)), .selection(bounds))
      ])
    #expect(harness.translator.requests.isEmpty)
  }

  @Test func aTypedWordIsLookedUp() async throws {
    let harness = Harness([(.failure(.nothingSelected(fieldText: nil)), nil)])
    harness.entries = [runEntry]
    await harness.press()

    harness.coordinator.submitted("ran")
    await harness.coordinator.settle()
    #expect(harness.panel.lastCard?.lemma == "run")
    #expect(harness.panel.lastCard?.context == nil)
    let encounter = try await harness.vocab?.day(today).lookups.first?.encounter
    #expect(encounter?.source == .typed)
    #expect(encounter?.sentence == nil)
  }
}
