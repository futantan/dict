// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore

/// The parts of the result panel a session drives (architecture 11.1).
@MainActor
protocol SessionPanel: AnyObject {
  var isVisible: Bool { get }
  func show(_ state: PanelState, near anchor: PanelAnchor)
  func update(_ state: PanelState)
  func hide()
}

extension PanelController: SessionPanel {}

/// Turns text into panel states; `TranslationEngine` in the app.
@MainActor
protocol SessionTranslator {
  func translate(
    _ text: String, direction: Direction, pair: LanguagePair, update: (PanelState) -> Void
  ) async
}

extension TranslationEngine: SessionTranslator {}

/// Proofreads text for the Write key; `Proofreader` in the app.
@MainActor
protocol SessionProofreader {
  func proofread(_ text: String) async throws -> AppliedEdits
}

extension Proofreader: SessionProofreader {}

/// Runs one operation at a time: the "read" shortcut captures the selection, shows the panel
/// and translates (architecture 2.1, 15.1); the "write" shortcut proofreads the selection,
/// shows the corrections as a diff, and Return replaces the selection (architecture 4.4).
///
/// Every operation gets a new session id. Hiding the panel (also by pressing the shortcut
/// again) and opening a window cancel the running task, and anything that arrives for an
/// older id is dropped, so a late result never lands in a newer panel (architecture 6.4).
/// A press while the selection is still being read, before the panel shows, is ignored.
/// When the first stage reads nothing, the panel shows "reading" at the mouse before the
/// clipboard fallback, and the outcome then replaces it in place.
@MainActor
final class SessionCoordinator {
  struct Environment {
    /// A translator for the current settings; called once per translation, so settings
    /// changes apply to the next one.
    var makeTranslator: () -> any SessionTranslator
    var languagePair: () -> LanguagePair
    /// Reads the permissions again; called whenever a session starts.
    var refreshPermissions: () -> PermissionStatus
    var permissionNotice: (PermissionIssue) -> PanelNotice
    /// Handles a permission notice button; false for ids it does not know.
    var performPermissionAction: (PanelAction.ID) -> Bool
    /// Opens Settings on the Model pane.
    var openSettings: () -> Void
    var mouseLocation: () -> CGPoint
    /// A proofreader for the current settings; nil without a usable model.
    var makeProofreader: () -> (any SessionProofreader)?
    var replaceWriter: any ReplaceWriter
    /// Reports how a replacement went, near the selection when its bounds are known.
    var showToast: (ToastMessage, CGRect?) -> Void
  }

  private let reader: any SelectionReader
  private let panel: any SessionPanel
  private let environment: Environment
  private var id = 0
  private var task: Task<Void, Never>?
  /// The text of the current session, for "Try Again".
  private var text: String?
  /// What the current session does with its text.
  private var role = HotkeyRole.read
  /// Where Return writes the correction, while the panel shows one.
  private var target: ReplaceTarget?
  private var targetBounds: CGRect?
  /// The last phase the Write flow showed, for Return.
  private var currentPhase: PanelPhase?
  private var replacement: Task<Void, Never>?
  /// The panel shows a permission notice; a grant reads the selection again.
  private var awaitsPermission = false
  /// A capture is running. It may be in the clipboard fallback, whose snapshot and restore
  /// must not interleave with another capture's.
  private var isCapturing = false

  init(reader: any SelectionReader, panel: any SessionPanel, environment: Environment) {
    self.reader = reader
    self.panel = panel
    self.environment = environment
  }

  // MARK: - Events

  func hotkeyPressed(_ role: HotkeyRole) {
    // Either shortcut hides a visible panel (architecture 10.1), also the reading panel
    // shown during the clipboard fallback.
    if panel.isVisible {
      end()
      return
    }
    // A capture is still running, or winding down after a cancel: a second capture could
    // snapshot the first one's copy as the user's clipboard, so the press is ignored.
    if isCapturing {
      Log.ui.info(
        "\(role.rawValue, privacy: .public) shortcut pressed while reading the selection: ignored")
      return
    }
    read(role)
  }

  /// Return in the panel: replaces the selection with the correction shown. The panel hides
  /// first, so the app the text came from is key again when the write happens (architecture
  /// 4.4, 11.2). A later session does not cancel the replacement: once it may have pasted,
  /// stopping halfway would leave the result on the clipboard.
  func confirm() {
    guard panel.isVisible, let target, case .corrected(let correction) = currentPhase,
      correction.canReplace
    else { return }
    let bounds = targetBounds
    let writer = environment.replaceWriter
    let showToast = environment.showToast
    let id = id
    cancel()
    panel.hide()
    Log.ui.info("session \(id, privacy: .public): replacing")
    replacement = Task {
      let outcome = await writer.replace(target, with: correction.text)
      Log.replace.info(
        "session \(id, privacy: .public): \(String(describing: outcome), privacy: .public)")
      showToast(ToastMessage(outcome, result: correction.text), bounds)
    }
  }

  /// The panel hid itself (Esc, a click outside, another app); the session ends.
  func panelDismissed(_ reason: PanelDismissal) {
    cancel()
  }

  /// Text typed into the empty panel and submitted.
  func submitted(_ text: String) {
    translate(text, source: .typed)
  }

  /// Translates `text` in a newly shown panel without reading any selection, for the
  /// onboarding window's sample: a capture in Dict's own window reads nothing.
  func translateSample(_ text: String, near anchor: PanelAnchor) {
    cancel()
    role = .read
    self.text = text
    let id = id
    panel.show(PanelState(source: text, phase: .generating("")), near: anchor)
    Log.ui.info("session \(id, privacy: .public): translating the onboarding sample")
    let clock = ContinuousClock()
    let start = clock.now
    task = Task { await self.run(text, id: id, clock: clock, start: start) }
  }

  func perform(_ action: PanelAction.ID) {
    switch action {
    case TranslationStrings.retryAction:
      if let text {
        if role == .write { proofreadAgain(text) } else { translate(text, source: .retry) }
      }
    case TranslationStrings.openSettingsAction:
      end()
      environment.openSettings()
    default:
      if !environment.performPermissionAction(action) {
        Log.ui.error("unknown panel action \(action, privacy: .public)")
      }
    }
  }

  /// A permission was turned on. A panel still explaining it reads the selection again.
  func permissionsChanged(granted: Set<Permission>) {
    guard awaitsPermission, panel.isVisible, !granted.isEmpty else { return }
    Log.ui.info("session: permission granted, reading again")
    panel.hide()
    read(role)
  }

  /// Ends the session, for example because a window of Dict opens.
  func end() {
    cancel()
    panel.hide()
  }

  /// Waits for the latest task and replacement, cancelled or not, for tests.
  func settle() async {
    await task?.value
    await replacement?.value
  }

  // MARK: - Flow

  private func cancel() {
    id += 1
    // The cancelled task stays referenced so `settle()` can wait for it to wind down.
    task?.cancel()
    text = nil
    target = nil
    targetBounds = nil
    currentPhase = nil
    awaitsPermission = false
  }

  private func read(_ role: HotkeyRole) {
    cancel()
    self.role = role
    let id = id
    isCapturing = true
    task = Task { await self.read(id) }
  }

  private func read(_ id: Int) async {
    let clock = ContinuousClock()
    let start = clock.now
    let status = environment.refreshPermissions()
    var showedReading = false
    let result = await reader.capture(policy: .allowed) {
      guard id == self.id else { return }
      showedReading = true
      panel.show(PanelState(phase: .reading), near: .mouse(environment.mouseLocation()))
      Log.ui.info(
        """
        session \(id, privacy: .public): reading panel shown \
        \(milliseconds(clock.now - start), format: .fixed(precision: 1), privacy: .public)ms after the shortcut, before the clipboard fallback
        """)
    }
    isCapturing = false
    guard id == self.id, !Task.isCancelled else { return }
    let captured = clock.now - start
    // After the reading panel, every outcome replaces it where it is.
    let present: (PanelState, PanelAnchor) -> Void = { state, anchor in
      if showedReading {
        self.panel.update(state)
      } else {
        self.panel.show(state, near: anchor)
      }
    }

    switch result {
    case .success(let selection)
    where !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
      text = selection.text
      let anchor =
        selection.bounds.map(PanelAnchor.selection) ?? .mouse(environment.mouseLocation())
      if role == .write {
        target = selection.target
        targetBounds = selection.bounds
        currentPhase = .checking(selection.text)
        present(PanelState(phase: .checking(selection.text)), anchor)
        Log.ui.info(
          """
          session \(id, privacy: .public): capture \(milliseconds(captured), format: .fixed(precision: 1), privacy: .public)ms \
          via \(selection.source.caseName, privacy: .public), replaceable \(selection.target != nil, privacy: .public)
          """)
        await proofread(selection.text, id: id)
        return
      }
      // Apple Translation gets its session through the panel's view, so the panel is shown
      // before translating (architecture 6.5).
      present(PanelState(source: selection.text, phase: .generating("")), anchor)
      Log.ui.info(
        """
        session \(id, privacy: .public): capture \(milliseconds(captured), format: .fixed(precision: 1), privacy: .public)ms \
        via \(selection.source.caseName, privacy: .public), panel shown \
        \(milliseconds(clock.now - start), format: .fixed(precision: 1), privacy: .public)ms after the shortcut
        """)
      await run(selection.text, id: id, clock: clock, start: start)
    case .success, .failure(.nothingSelected):
      // Proofreading has no input field: it works on text written somewhere else.
      let state =
        role == .write ? PanelState(phase: .failure(WritingStrings.nothingToCheck)) : .input
      show(state, captured: captured, outcome: "nothingSelected", present: present)
    case .failure(.ownApp):
      Log.ui.info("session \(id, privacy: .public): Dict itself is in front; nothing to read")
    case .failure(let failure):
      if let issue = PermissionIssue(failure, status: status) {
        awaitsPermission = true
        show(
          PanelState(phase: .needsSetup(environment.permissionNotice(issue))), captured: captured,
          outcome: failure.caseName, present: present)
      } else {
        show(
          PanelState(phase: .failure(SessionStrings.captureFailure(failure))), captured: captured,
          outcome: failure.logDescription, present: present)
      }
    }
  }

  private func show(
    _ state: PanelState, captured: Duration, outcome: String,
    present: (PanelState, PanelAnchor) -> Void
  ) {
    present(state, .mouse(environment.mouseLocation()))
    Log.ui.info(
      """
      session \(self.id, privacy: .public): capture \(milliseconds(captured), format: .fixed(precision: 1), privacy: .public)ms \
      \(outcome, privacy: .public), panel shown
      """)
  }

  /// Proofreads in the visible panel and shows the diff.
  private func proofread(_ text: String, id: Int) async {
    self.text = text
    guard let proofreader = environment.makeProofreader() else {
      show(PanelState(phase: .needsSetup(WritingStrings.needsModel)), id: id)
      return
    }
    let clock = ContinuousClock()
    let start = clock.now
    do {
      let applied = try await proofreader.proofread(text)
      guard id == self.id, !Task.isCancelled else { return }
      show(PanelState(phase: .corrected(Correction(applied, replaceable: target != nil))), id: id)
      Log.ui.info(
        """
        session \(id, privacy: .public): proofread, \(applied.changeCount, privacy: .public) changes \
        after \(milliseconds(clock.now - start), format: .fixed(precision: 1), privacy: .public)ms
        """)
    } catch {
      guard id == self.id, !Task.isCancelled, !(error is CancellationError) else { return }
      // A ProofreadError holds only indices, never the user's text.
      let reason = error is ProofreadError ? String(describing: error) : "\(type(of: error))"
      Log.model.error("proofread failed: \(reason, privacy: .public)")
      show(PanelState(phase: .failure(WritingStrings.proofreadFailure(error))), id: id)
    }
  }

  /// "Try Again" after a failed proofread, keeping the session's target.
  private func proofreadAgain(_ text: String) {
    guard panel.isVisible else { return }
    let target = target
    let bounds = targetBounds
    cancel()
    self.target = target
    targetBounds = bounds
    let id = id
    show(PanelState(phase: .checking(text)), id: id)
    task = Task { await self.proofread(text, id: id) }
  }

  private func show(_ state: PanelState, id: Int) {
    guard id == self.id else { return }
    currentPhase = state.phase
    panel.update(state)
  }

  private enum Origin: String { case typed, retry }

  /// Translates in the visible panel, as a new session.
  private func translate(_ text: String, source: Origin) {
    guard panel.isVisible else { return }
    cancel()
    self.text = text
    let id = id
    panel.update(PanelState(source: text, phase: .generating("")))
    Log.ui.info(
      "session \(id, privacy: .public): translating \(source.rawValue, privacy: .public) text")
    let clock = ContinuousClock()
    let start = clock.now
    task = Task { await self.run(text, id: id, clock: clock, start: start) }
  }

  private func run(_ text: String, id: Int, clock: ContinuousClock, start: ContinuousClock.Instant)
    async
  {
    let pair = environment.languagePair()
    let direction = resolveDirection(text, pair: pair)
    var firstText: Duration?
    var last: PanelPhase?
    await environment.makeTranslator().translate(text, direction: direction, pair: pair) {
      state in
      guard id == self.id else { return }
      if firstText == nil, state.phase.copyableText != nil {
        firstText = clock.now - start
        Log.ui.info(
          "session \(id, privacy: .public): first text \(milliseconds(clock.now - start), format: .fixed(precision: 1), privacy: .public)ms after the shortcut"
        )
      }
      last = state.phase
      panel.update(state)
    }
    guard id == self.id, !Task.isCancelled else {
      Log.ui.info("session \(id, privacy: .public): cancelled")
      return
    }
    Log.ui.info(
      """
      session \(id, privacy: .public): \(String(describing: direction), privacy: .public) ended \
      in \(last?.name ?? "-", privacy: .public) after \
      \(milliseconds(clock.now - start), format: .fixed(precision: 1), privacy: .public)ms
      """)
  }
}
