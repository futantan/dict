// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore

/// The parts of the result panel a session drives (architecture 11.1).
@MainActor
protocol SessionPanel: AnyObject {
  var isVisible: Bool { get }
  /// The correction shown, with the changes the user accepted: the panel keeps that review
  /// itself (`PanelController.review`). Nil when no correction is shown or the panel cannot
  /// tell, and then every change counts as accepted.
  var reviewedCorrection: Correction? { get }
  func show(_ state: PanelState, near anchor: PanelAnchor)
  func update(_ state: PanelState)
  func hide()
}

extension SessionPanel {
  var reviewedCorrection: Correction? { nil }
}

extension PanelController: SessionPanel {
  var reviewedCorrection: Correction? {
    if case .corrected(let correction) = state.phase { correction } else { nil }
  }
}

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
/// and translates (architecture 2.1, 15.1); the "write" shortcut translates a selection in my
/// language into the learning language and translates it back for checking, or proofreads
/// anything else and shows the corrections as a diff (`writeAction`); Return replaces the
/// selection (architecture 4.4).
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
    /// The dictionary layer: the entries for a term read in a sentence; none without a
    /// dictionary (architecture 7.4).
    var lookUpTerm: @MainActor (String, String?) async -> [LexiconEntry] = { _, _ in [] }
    /// A card maker for the current settings; nil without a usable model.
    var makeCardMaker: () -> CardMaker? = { nil }
    /// The vocabulary log; nil when it could not be opened, and then nothing is recorded.
    var vocab: (any SessionVocab)?
    /// The accent the card's pronunciation is shown and spoken in.
    var accent: () -> Accent = { .american }
    /// Says a word in a language at a rate (architecture 9).
    var pronounce: (String, Locale.Language, SpeechRate) -> Void = { _, _, _ in }
    /// Today in the user's time zone, for the vocabulary log.
    var today: () -> LocalDay = { LocalDay(.now, in: .current) }
    /// A translate-out engine for the current settings; nil when there is none, which the
    /// panel shows as a model to set up.
    var makeTranslateOut: () -> (any SessionTranslateOut)? = { nil }
  }

  /// Where the session's text came from, for the vocabulary log (architecture 8.1).
  struct TextOrigin {
    var context: ContextSentence?
    var source: LookupSource
    /// Bundle id.
    var app: String?

    static let typed = TextOrigin(context: nil, source: .typed, app: nil)
  }

  private let reader: any SelectionReader
  private let panel: any SessionPanel
  private let environment: Environment
  private var id = 0
  private var task: Task<Void, Never>?
  /// The text of the current session, for "Try Again" and switching between the card and
  /// the translation.
  private var text: String?
  /// Where `text` came from; nil for the onboarding sample, which is not recorded.
  private var origin: TextOrigin?
  /// The current Read session shows a card rather than a translation.
  private var showsCard = false
  /// The card shown, and the note under it, while the session shows one.
  private var card: CardState?
  private var cardNote: PanelNote?
  /// The looked-up term as the vocabulary log has it, once this lookup is recorded. Kept
  /// across "Try Again" and switching to the translation and back, which show the same
  /// lookup again rather than a new one.
  private var recorded: TermSummary?
  /// The latest ⌘S, for `settle()`.
  private var tierChange: Task<Void, Never>?
  private var pace = PronunciationPace()
  /// The text has neither a dictionary entry nor a model to explain it, so looking it up
  /// would only translate it again; kept like `recorded`.
  private var cannotLookUp = false
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

  /// Return in the panel: replaces the selection with the changes the user accepted, or with
  /// the translation. The panel hides first, so the app the text came from is key again when
  /// the write happens (architecture 4.4, 11.2). A later session does not cancel the
  /// replacement: once it may have pasted, stopping halfway would leave the result on the
  /// clipboard. With every change declined nothing is replaced, and the panel stays and says
  /// so. A translation with issues is replaced only `anyway`, on ⌘Return.
  func confirm(anyway: Bool = false) {
    guard panel.isVisible, let target else { return }
    switch currentPhase {
    case .corrected(let shown) where shown.canReplace:
      confirm(shown, target: target)
    case .translatedOut(let shown) where anyway ? shown.canReplace : shown.replacesOnReturn:
      let pair = environment.languagePair()
      replace(target, with: shown.text, why: "translation") { source, applied in
        await self.recordSentence(
          .translatedOut, source: source, result: shown.text, applied: applied,
          app: target.app.bundleID, languages: (pair.mine, pair.learning))
      }
    default:
      break
    }
  }

  private func confirm(_ shown: Correction, target: ReplaceTarget) {
    var correction = shown
    if let reviewed = panel.reviewedCorrection, reviewed.proposed == shown.proposed {
      correction = reviewed
    }
    guard !correction.accepted.isEmpty else {
      correction.declinedReturn = true
      show(PanelState(phase: .corrected(correction)), id: id)
      Log.ui.info("session \(self.id, privacy: .public): every change declined, nothing replaced")
      return
    }
    replace(target, with: correction.text, why: "correction") { source, applied in
      await self.recordSentence(
        .corrected, source: source, result: correction.text, edits: correction.editsJSON,
        applied: applied, app: target.app.bundleID)
    }
  }

  /// Hides the panel, ends the session, writes `result`, reports the outcome with a toast,
  /// then records the session's text with whether it was replaced.
  private func replace(
    _ target: ReplaceTarget, with result: String, why: String,
    record: @escaping (_ source: String, _ applied: Bool) async -> Void
  ) {
    let bounds = targetBounds
    let writer = environment.replaceWriter
    let showToast = environment.showToast
    let id = id
    let source = text
    cancel()
    panel.hide()
    Log.ui.info("session \(id, privacy: .public): replacing with the \(why, privacy: .public)")
    replacement = Task {
      let outcome = await writer.replace(target, with: result)
      Log.replace.info(
        "session \(id, privacy: .public): \(String(describing: outcome), privacy: .public)")
      showToast(ToastMessage(outcome, result: result), bounds)
      if let source {
        let applied = if case .replaced = outcome { true } else { false }
        await record(source, applied)
      }
    }
  }

  /// The panel hid itself (Esc, a click outside, another app); the session ends.
  func panelDismissed(_ reason: PanelDismissal) {
    cancel()
  }

  /// Text typed into the empty panel and submitted; routed like a selection.
  func submitted(_ text: String) {
    start(
      text, as: readRoute(text, pair: environment.languagePair()), origin: .typed, why: "typed")
  }

  /// Translates `text` in a newly shown panel without reading any selection, for the
  /// onboarding window's sample: a capture in Dict's own window reads nothing.
  func translateSample(_ text: String, near anchor: PanelAnchor) {
    cancel()
    role = .read
    self.text = text
    origin = nil
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
        if role == .write {
          writeAgain(text)
        } else {
          start(
            text, as: showsCard ? .lookUp : .translate, origin: origin, why: "retry",
            keepingRecord: true)
        }
      }
    case CardStrings.translateAction:
      if let text, showsCard {
        start(text, as: .translate, origin: origin, why: "switch", keepingRecord: true)
      }
    case CardStrings.lookUpAction:
      if let text, !showsCard, role == .read, offersLookUp(text) {
        start(text, as: .lookUp, origin: origin, why: "switch", keepingRecord: true)
      }
    case CardStrings.learnAction:
      toggleLearning()
    case CardStrings.pronounceAction:
      pronounce()
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
    await tierChange?.value
  }

  // MARK: - Flow

  private func cancel() {
    id += 1
    // The cancelled task stays referenced so `settle()` can wait for it to wind down.
    task?.cancel()
    text = nil
    origin = nil
    showsCard = false
    card = nil
    cardNote = nil
    recorded = nil
    pace = PronunciationPace()
    cannotLookUp = false
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
      origin = TextOrigin(
        context: selection.context, source: LookupSource(selection.source),
        app: selection.app?.bundleID)
      let anchor =
        selection.bounds.map(PanelAnchor.selection) ?? .mouse(environment.mouseLocation())
      if role == .write {
        target = selection.target
        targetBounds = selection.bounds
        let action = writeAction(for: selection.text, pair: environment.languagePair())
        let first = firstWriteState(selection.text, action: action)
        currentPhase = first.phase
        present(first, anchor)
        Log.ui.info(
          """
          session \(id, privacy: .public): capture \(milliseconds(captured), format: .fixed(precision: 1), privacy: .public)ms \
          via \(selection.source.caseName, privacy: .public), \(String(describing: action), privacy: .public), \
          replaceable \(selection.target != nil, privacy: .public)
          """)
        await write(selection.text, action: action, id: id)
        return
      }
      let route = readRoute(selection.text, pair: environment.languagePair())
      Log.ui.info(
        """
        session \(id, privacy: .public): capture \(milliseconds(captured), format: .fixed(precision: 1), privacy: .public)ms \
        via \(selection.source.caseName, privacy: .public), \(String(describing: route), privacy: .public)
        """)
      switch route {
      case .nothing:
        present(PanelState(phase: .failure(CardStrings.nothingToLookUp)), anchor)
      case .lookUp:
        await lookUp(selection.text, id: id, clock: clock, start: start) { present($0, anchor) }
      case .translate:
        // Apple Translation gets its session through the panel's view, so the panel is
        // shown before translating (architecture 6.5).
        present(translating(selection.text), anchor)
        Log.ui.info(
          "session \(id, privacy: .public): panel shown \(milliseconds(clock.now - start), format: .fixed(precision: 1), privacy: .public)ms after the shortcut"
        )
        await run(selection.text, id: id, clock: clock, start: start)
      }
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

  /// The Write key's first state: the translation about to stream in, or the text being
  /// proofread.
  private func firstWriteState(_ text: String, action: Capability) -> PanelState {
    action == .translateOut
      ? PanelState(source: text, phase: .translatedOut(TranslateOut(replaceable: target != nil)))
      : PanelState(phase: .checking(text))
  }

  private func write(_ text: String, action: Capability, id: Int) async {
    if action == .translateOut {
      await translateOut(text, id: id)
    } else {
      await proofread(text, id: id)
    }
  }

  /// Translates out in the visible panel, then translates back (architecture 6.6). Every
  /// state goes through `show(_:id:)`, so Return sees the latest.
  private func translateOut(_ text: String, id: Int) async {
    self.text = text
    guard let engine = environment.makeTranslateOut() else {
      show(PanelState(phase: .needsSetup(TranslationStrings.needsModel)), id: id)
      return
    }
    let clock = ContinuousClock()
    let start = clock.now
    let pair = environment.languagePair()
    let context = appContext(bundleID: origin?.app)
    let replaceable = target != nil
    var last: PanelPhase?
    await engine.translateOut(text, pair: pair, context: context) { state in
      guard id == self.id else { return }
      var state = state
      if case .translatedOut(var translation) = state.phase {
        translation.replaceable = replaceable
        state.phase = .translatedOut(translation)
      }
      last = state.phase
      show(state, id: id)
    }
    guard id == self.id, !Task.isCancelled else { return }
    var issues = "-"
    if case .translatedOut(let translation) = last {
      issues = translation.issues.map { "\($0)" }.joined(separator: ",")
    }
    Log.ui.info(
      """
      session \(id, privacy: .public): translate-out (\(context.rawValue, privacy: .public)) ended \
      in \(last?.name ?? "-", privacy: .public), issues [\(issues, privacy: .public)], after \
      \(milliseconds(clock.now - start), format: .fixed(precision: 1), privacy: .public)ms
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

  /// "Try Again" after a failed proofread or translate-out, keeping the session's target and
  /// where the text came from.
  private func writeAgain(_ text: String) {
    guard panel.isVisible else { return }
    let target = target
    let bounds = targetBounds
    let origin = origin
    cancel()
    self.target = target
    targetBounds = bounds
    self.origin = origin
    let id = id
    let action = writeAction(for: text, pair: environment.languagePair())
    show(firstWriteState(text, action: action), id: id)
    task = Task { await self.write(text, action: action, id: id) }
  }

  private func show(_ state: PanelState, id: Int) {
    guard id == self.id else { return }
    currentPhase = state.phase
    panel.update(state)
  }

  /// Handles `text` in the visible panel as a new Read session: typed text, "Try Again",
  /// and switching between the card and the translation.
  private func start(
    _ text: String, as route: ReadRoute, origin: TextOrigin?, why: String,
    keepingRecord: Bool = false
  ) {
    guard panel.isVisible else { return }
    let recorded = keepingRecord ? recorded : nil
    let cannotLookUp = keepingRecord && cannotLookUp
    cancel()
    role = .read
    self.text = text
    self.origin = origin
    self.recorded = recorded
    self.cannotLookUp = cannotLookUp
    let id = id
    Log.ui.info(
      "session \(id, privacy: .public): \(why, privacy: .public) text, \(String(describing: route), privacy: .public)"
    )
    let clock = ContinuousClock()
    let start = clock.now
    switch route {
    case .nothing:
      show(PanelState(phase: .failure(CardStrings.nothingToLookUp)), id: id)
    case .translate:
      panel.update(translating(text))
      task = Task { await self.run(text, id: id, clock: clock, start: start) }
    case .lookUp:
      task = Task {
        await self.lookUp(text, id: id, clock: clock, start: start) { self.panel.update($0) }
      }
    }
  }

  /// The first state of a translation.
  private func translating(_ text: String) -> PanelState {
    PanelState(source: text, phase: .generating(""), offersLookUp: offersLookUp(text))
  }

  /// A translation of a word or phrase offers looking it up instead (architecture 5.1).
  private func offersLookUp(_ text: String) -> Bool {
    role == .read && !cannotLookUp && [.word, .phrase].contains(classify(text))
  }

  private func run(_ text: String, id: Int, clock: ContinuousClock, start: ContinuousClock.Instant)
    async
  {
    let pair = environment.languagePair()
    let direction = resolveDirection(text, pair: pair)
    var firstText: Duration?
    var last: PanelPhase?
    let offersLookUp = offersLookUp(text)
    showsCard = false
    await environment.makeTranslator().translate(text, direction: direction, pair: pair) {
      state in
      guard id == self.id else { return }
      var state = state
      state.offersLookUp = offersLookUp
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
    // A word or phrase translated is no sentence; its lookups are what the log keeps.
    if case .result(let result) = last, let origin, classify(text) == .passage {
      let intoLearning = direction == .intoLearning
      await recordSentence(
        .translated, source: text, result: result, app: origin.app,
        languages: intoLearning ? (pair.mine, pair.learning) : (pair.learning, pair.mine))
    }
  }

  // MARK: - Word card

  /// Shows the card of `text`: the dictionary layer at once through `present`, then the
  /// model's card as it streams in (architecture 6.6). Without either, translates instead,
  /// which can still use Apple Translation; so does a model that says the text is no term.
  private func lookUp(
    _ text: String, id: Int, clock: ContinuousClock, start: ContinuousClock.Instant,
    present: (PanelState) -> Void
  ) async {
    let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let context = origin?.context?.sentence
    let lookupStart = clock.now
    let entries = await environment.lookUpTerm(term, context)
    let dictionaryTime = clock.now - lookupStart
    guard id == self.id, !Task.isCancelled else { return }
    let maker = environment.makeCardMaker()
    if entries.isEmpty && maker == nil {
      Log.ui.info("session \(id, privacy: .public): no dictionary entry and no model; translating")
      cannotLookUp = true
      present(translating(text))
      await run(text, id: id, clock: clock, start: start)
      return
    }
    showsCard = true
    card = CardState(
      term: term, context: context, entry: entries.first, accent: environment.accent(),
      model: maker == nil ? .unavailable : .loading)
    cardNote = maker == nil ? CardStrings.needsModelNote : nil
    present(cardPanel)
    Log.ui.info(
      """
      session \(id, privacy: .public): card shown \(milliseconds(clock.now - start), format: .fixed(precision: 1), privacy: .public)ms \
      after the shortcut, \(entries.count, privacy: .public) dictionary entries in \
      \(milliseconds(dictionaryTime), format: .fixed(precision: 2), privacy: .public)ms
      """)
    // A dictionary entry makes it a term at once; otherwise the model's first field does,
    // since `status` comes before every field and a non-term ends the stream.
    // The request starts before the lookup is recorded, so the write is not on the way to
    // the first field; the stream keeps what arrives meanwhile.
    let stream = maker?.card(
      term: term, context: context, pair: environment.languagePair(),
      accent: environment.accent())
    let lemma = entries.first?.lemma ?? term
    if let recorded {
      showRecorded(recorded)
    } else if !entries.isEmpty {
      await recordLookup(term, lemma: lemma, id: id)
    }
    guard let stream, id == self.id, !Task.isCancelled else { return }

    do {
      for try await event in stream {
        guard id == self.id else { return }
        switch event {
        case .fields(let definition, let translation):
          card?.show(definition: definition, contextTranslation: translation)
        case .card(let complete):
          card?.show(complete)
        case .notATerm:
          Log.ui.info("session \(id, privacy: .public): the model says no term; translating")
          showsCard = false
          card = nil
          panel.update(translating(text))
          await run(text, id: id, clock: clock, start: start)
          return
        }
        panel.update(cardPanel)
        if recorded == nil { await recordLookup(term, lemma: lemma, id: id) }
      }
      Log.ui.info(
        "session \(id, privacy: .public): card complete \(milliseconds(clock.now - start), format: .fixed(precision: 1), privacy: .public)ms after the shortcut"
      )
    } catch {
      guard id == self.id, !Task.isCancelled, !(error is CancellationError) else { return }
      Log.model.error("card failed: \(String(describing: error), privacy: .public)")
      card?.model = .unavailable
      cardNote = CardStrings.failureNote(error)
      panel.update(cardPanel)
    }
  }

  private var cardPanel: PanelState {
    guard let card else { return PanelState(phase: .reading) }
    return PanelState(phase: .card(card), note: cardNote)
  }

  /// Records the lookup and shows its count; a failure is logged and the card stays.
  private func recordLookup(_ term: String, lemma: String, id: Int) async {
    guard let vocab = environment.vocab, let origin else { return }
    let context = origin.context
    let range = context.map { context in
      let utf16 = context.sentence.utf16
      return (
        start: utf16.distance(from: utf16.startIndex, to: context.termRange.lowerBound),
        length: utf16.distance(
          from: context.termRange.lowerBound, to: context.termRange.upperBound)
      )
    }
    let record = LookupRecord(
      language: environment.languagePair().learning.languageCode?.identifier ?? "en",
      lemma: lemma, surface: term, sentence: context?.sentence, termStart: range?.start,
      termLength: range?.length, source: origin.source, sourceApp: origin.app,
      day: environment.today(), seenAt: .now)
    do {
      let summary = try await vocab.recordLookup(record)
      guard id == self.id else { return }
      recorded = summary
      showRecorded(summary)
    } catch {
      Log.store.error(
        "recording the lookup failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// The count and tier of the recorded term on the card.
  private func showRecorded(_ summary: TermSummary) {
    card?.encounters = summary.encounterCount
    card?.isLearning = summary.tier == .learning
    panel.update(cardPanel)
  }

  /// ⌘S: marks the term 要学, or back to 查过 (architecture 8.3).
  private func toggleLearning() {
    guard let vocab = environment.vocab, let recorded, card != nil else { return }
    let tier: Tier = recorded.tier == .learning ? .seen : .learning
    let id = id
    let day = environment.today()
    tierChange = Task {
      do {
        try await vocab.setTier(tier, termID: recorded.id, on: day)
        guard id == self.id else { return }
        self.recorded?.tier = tier
        if let summary = self.recorded { self.showRecorded(summary) }
      } catch {
        Log.store.error(
          "changing the tier failed: \(String(describing: error), privacy: .public)")
      }
    }
  }

  /// ⌘P: says the card's title, slowly when pressed again right away.
  private func pronounce() {
    guard let card else { return }
    environment.pronounce(
      card.lemma, environment.languagePair().learning, pace.next(at: ContinuousClock.now))
  }

  // MARK: - Recording

  /// Records a finished translation or correction; a failure is only logged (architecture
  /// 8.1). Without `languages`, both sides are the learning language, as for a correction.
  private func recordSentence(
    _ kind: SentenceKind, source: String, result: String, edits editsJSON: String? = nil,
    applied: Bool = false, app: String?, languages: (Locale.Language, Locale.Language)? = nil
  ) async {
    guard let vocab = environment.vocab else { return }
    let learning = environment.languagePair().learning
    let (from, to) = languages ?? (learning, learning)
    let record = SentenceRecord(
      kind: kind, source: source, result: result, editsJSON: editsJSON, applied: applied,
      sourceLanguage: from.languageCode?.identifier ?? "",
      resultLanguage: to.languageCode?.identifier ?? "", sourceApp: app,
      day: environment.today(), createdAt: .now)
    do {
      try await vocab.recordSentence(record)
    } catch {
      Log.store.error(
        "recording a \(kind.rawValue, privacy: .public) sentence failed: \(String(describing: error), privacy: .public)"
      )
    }
  }
}

extension Correction {
  /// The accepted changes as the vocabulary log stores them: `[{"right": …, "wrong": …}]`.
  var editsJSON: String? {
    let edits = result.segments.compactMap { segment -> [String: String]? in
      guard case .changed(let wrong, let right) = segment else { return nil }
      return ["wrong": wrong, "right": right]
    }
    guard let data = try? JSONSerialization.data(withJSONObject: edits, options: .sortedKeys)
    else { return nil }
    return String(decoding: data, as: UTF8.self)
  }
}
