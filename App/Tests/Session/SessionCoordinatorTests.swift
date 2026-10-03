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

/// Answers each capture with the next scripted result, optionally after a gate.
@MainActor
private final class StubReader: SelectionReader {
  var results: [(Result<Selection, CaptureFailure>, Gate?)]
  private(set) var calls = 0

  init(_ results: [(Result<Selection, CaptureFailure>, Gate?)]) { self.results = results }

  func capture(policy: ClipboardPolicy) async -> Result<Selection, CaptureFailure> {
    #expect(policy == .allowed)
    calls += 1
    let (result, gate) = results.removeFirst()
    await gate?.wait()
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

/// Reports scripted states, optionally waiting at a gate after the first one.
@MainActor
private final class StubTranslator: SessionTranslator {
  var states: [PanelPhase]
  var gate: Gate?
  private(set) var requests: [(text: String, direction: Direction)] = []
  private(set) var sawCancellation = false

  init(_ states: [PanelPhase], gate: Gate? = nil) {
    self.states = states
    self.gate = gate
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
      update(PanelState(source: text, phase: phase))
    }
  }
}

private let bounds = CGRect(x: 100, y: 500, width: 200, height: 20)
private let mouse = CGPoint(x: 40, y: 60)
private let granted = PermissionStatus(accessibility: true, postEvent: true)
private let app = TargetApp(pid: 42, bundleID: "com.apple.TextEdit", launchDate: nil, kind: .native)

private func selection(_ text: String, bounds: CGRect? = bounds) -> Selection {
  Selection(
    text: text, source: .accessibility, app: app, bounds: bounds, context: nil, target: nil)
}

@MainActor
private final class Harness {
  let reader: StubReader
  let panel = FakePanel()
  let translator: StubTranslator
  var status = granted
  var opened: [String] = []
  var permissionActions: [PanelAction.ID] = []
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
      openLanguageDownload: { [unowned self] in opened.append("languages") },
      mouseLocation: { mouse }))

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

private func notice(_ issue: PermissionIssue) -> PanelNotice {
  PermissionGuide.notice(for: issue, app: .init(name: "Dict", bundleID: "x"))
}

@MainActor
struct SessionCoordinatorTests {
  @Test func readShowsTheSelectionThenTheTranslation() async {
    let harness = Harness([(.success(selection("Hello")), nil)])
    await harness.press()

    #expect(
      harness.panel.calls == [
        .show(PanelState(source: "Hello", phase: .generating("")), .selection(bounds)),
        .update(PanelState(source: "Hello", phase: .generating("你"))),
        .update(PanelState(source: "Hello", phase: .result("你好"))),
      ])
    #expect(harness.translator.requests.map(\.text) == ["Hello"])
    #expect(harness.translator.requests.map(\.direction) == [.intoMine])
  }

  @Test func withoutBoundsThePanelGoesToTheMouse() async {
    let harness = Harness([(.success(selection("你好", bounds: nil)), nil)])
    await harness.press()

    #expect(
      harness.panel.calls.first
        == .show(PanelState(source: "你好", phase: .generating("")), .mouse(mouse)))
    #expect(harness.translator.requests.map(\.direction) == [.intoLearning])
  }

  @Test func nothingSelectedOpensTheInputThenTranslatesTypedText() async {
    let harness = Harness([(.failure(.nothingSelected(fieldText: nil)), nil)])
    await harness.press()
    #expect(harness.panel.calls == [.show(.input, .mouse(mouse))])

    harness.coordinator.submitted("Bonjour")
    await harness.coordinator.settle()

    #expect(harness.translator.requests.map(\.text) == ["Bonjour"])
    #expect(
      harness.panel.calls.dropFirst().first
        == .update(PanelState(source: "Bonjour", phase: .generating(""))))
    #expect(
      harness.panel.calls.last == .update(PanelState(source: "Bonjour", phase: .result("你好"))))
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
      (.failure(.noAccessibilityPermission), nil), (.success(selection("Hello")), nil),
    ])
    harness.status = PermissionStatus(accessibility: false, postEvent: true)
    await harness.press()

    harness.status = granted
    harness.coordinator.permissionsChanged(granted: [.accessibility])
    await harness.coordinator.settle()

    #expect(harness.reader.calls == 2)
    #expect(harness.panel.calls[1] == .hide)
    #expect(harness.panel.calls.last == .update(PanelState(source: "Hello", phase: .result("你好"))))
  }

  @Test func grantWithoutAWaitingSessionDoesNothing() async {
    let harness = Harness([(.success(selection("Hello")), nil)])
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

  /// The write shortcut has no action until writing help exists (architecture 15.1).
  @Test func writeDoesNothing() async {
    let harness = Harness([(.success(selection("Hello")), nil)])
    await harness.press(.write)

    #expect(harness.reader.calls == 0)
    #expect(harness.panel.calls.isEmpty)
  }

  @Test func aNewPressCancelsTheCaptureInFlight() async {
    let slow = Gate()
    let harness = Harness([
      (.success(selection("First")), slow), (.success(selection("Second")), nil),
    ])
    harness.coordinator.hotkeyPressed(.read)
    await Task.yield()
    harness.coordinator.hotkeyPressed(.read)
    await harness.coordinator.settle()
    slow.open()
    for _ in 0..<10 { await Task.yield() }

    #expect(harness.translator.requests.map(\.text) == ["Second"])
    #expect(
      !harness.panel.calls.contains(
        .show(PanelState(source: "First", phase: .generating("")), .selection(bounds))))
  }

  @Test func theSameKeyWhileShownHidesAndCancels() async {
    let gate = Gate()
    let translator = StubTranslator([.generating("你"), .result("你好")], gate: gate)
    let harness = Harness([(.success(selection("Hello")), nil)], translator: translator)
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
      !harness.panel.calls.contains(.update(PanelState(source: "Hello", phase: .result("你好")))))
  }

  @Test func dismissingThePanelCancelsTheTranslation() async {
    let gate = Gate()
    let translator = StubTranslator([.generating("你"), .result("你好")], gate: gate)
    let harness = Harness([(.success(selection("Hello")), nil)], translator: translator)
    harness.coordinator.hotkeyPressed(.read)
    for _ in 0..<5 { await Task.yield() }

    harness.panel.dismissByUser()
    harness.coordinator.panelDismissed(.escape)
    gate.open()
    await harness.coordinator.settle()

    #expect(translator.sawCancellation)
    #expect(
      !harness.panel.calls.contains(.update(PanelState(source: "Hello", phase: .result("你好")))))
  }

  @Test func translationFailuresAreShownAsReported() async {
    let failure = PanelNotice(title: "The model couldn’t translate this")
    let harness = Harness(
      [(.success(selection("Hello")), nil)],
      translator: StubTranslator([.generating(""), .failure(failure)]))
    await harness.press()

    #expect(
      harness.panel.calls.last == .update(PanelState(source: "Hello", phase: .failure(failure))))
  }

  @Test func retryTranslatesTheSameTextAgain() async {
    let harness = Harness([(.success(selection("Hello")), nil)])
    await harness.press()

    harness.coordinator.perform(TranslationStrings.retryAction)
    await harness.coordinator.settle()

    #expect(harness.reader.calls == 1)
    #expect(harness.translator.requests.map(\.text) == ["Hello", "Hello"])
  }

  @Test func settingsAndDownloadActionsEndTheSession() async {
    let harness = Harness([(.success(selection("Hello")), nil), (.success(selection("Hi")), nil)])
    await harness.press()
    harness.coordinator.perform(TranslationStrings.openSettingsAction)
    #expect(harness.panel.calls.last == .hide)

    await harness.press()
    harness.coordinator.perform(TranslationStrings.downloadLanguagesAction)

    #expect(harness.opened == ["settings", "languages"])
    #expect(!harness.panel.isVisible)
  }

  @Test func permissionActionsGoToTheGuide() async {
    let harness = Harness([(.failure(.noAccessibilityPermission), nil)])
    harness.status = PermissionStatus(accessibility: false, postEvent: false)
    await harness.press()

    harness.coordinator.perform(PermissionGuide.ActionID.openSettings)

    #expect(harness.permissionActions == [PermissionGuide.ActionID.openSettings])
  }
}
