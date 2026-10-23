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
// `"translator": "model"` translates with the saved model settings and the Keychain key
// instead, as the app does; `"baseURL"` and `"apiKey"` override those two for failure tests.
// `"pressAgainAfterMs"` presses the shortcut once more and `"escapeAfterMs"` sends Esc to
// the panel, both counted from the first press.
// A word or phrase goes to the card as in the app, with a stub dictionary that knows every
// term and a stub card model, or the configured model with `"translator": "model"`; nothing
// is written to the vocabulary log.
// `write` presses the "write" shortcut instead, waits for the panel to finish (for a
// translate-out, the back-translation too), sends Return to the panel, then reads the
// field's value and formatting through accessibility, posts ⌘Z to the app and reads them
// again. It translates out and proofreads with stub models (`E2EStub.TranslateOutModel`,
// `E2EStub.ProofreadModel`) unless `"translator": "model"`.

#if DEBUG
  import AppKit
  import DictCore

  enum E2EStep: Equatable, Sendable {
    /// `content`, when given, first replaces the control's text.
    case select(control: String, text: String, content: String? = nil)
    case capture(ClipboardPolicy)
    case read(E2EReadOptions)
    /// Presses the write shortcut, confirms with Return, then undoes with ⌘Z.
    case write(E2EReadOptions)
    case wait(ms: Int)
    /// A step this runner does not understand; reported, then skipped.
    case invalid(String)
  }

  /// How a `read` step presses the shortcut and translates.
  struct E2EReadOptions: Equatable, Sendable {
    var force: ForcedCopy?
    /// Translate with the configured model rather than echo the text.
    var usesModel = false
    var baseURL: String?
    var apiKey: String?
    var pressAgainAfterMs: Int?
    var escapeAfterMs: Int?
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
        return .select(control: control, text: text, content: select["content"] as? String)
      }
      if let capture = object["capture"] as? [String: Any] {
        switch capture["policy"] as? String {
        case "allowed": return .capture(.allowed)
        case "never": return .capture(.never)
        default: return .invalid("capture policy must be allowed or never")
        }
      }
      if let read = object["read"] as? [String: Any] {
        var options = E2EReadOptions()
        if let force = read["force"] as? String {
          guard let forced = ForcedCopy(rawValue: force) else {
            return .invalid("read force must be menu or key")
          }
          options.force = forced
        }
        switch read["translator"] as? String {
        case nil, "echo": break
        case "model": options.usesModel = true
        default: return .invalid("read translator must be echo or model")
        }
        options.baseURL = read["baseURL"] as? String
        options.apiKey = read["apiKey"] as? String
        options.pressAgainAfterMs = read["pressAgainAfterMs"] as? Int
        options.escapeAfterMs = read["escapeAfterMs"] as? Int
        return .read(options)
      }
      if let write = object["write"] as? [String: Any] {
        var options = E2EReadOptions()
        switch write["translator"] as? String {
        case nil, "stub": break
        case "model": options.usesModel = true
        default: return .invalid("write translator must be stub or model")
        }
        return .write(options)
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
    case write(ms: Double, session: E2ESession.Record, report: CaptureReport?)
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
        object["translation"] = session.translation
        row = object
        return row
      case .write(let ms, let session, let report):
        guard
          var object = E2EResultRow.read(ms: ms, session: session, report: report).json
            as? [String: Any]
        else { return [:] }
        object["step"] = "write"
        object["write"] = session.write
        return object
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
        case .select(let control, let text, let content):
          var userInfo = ["command": "select", "control": control, "text": text]
          userInfo["content"] = content
          DistributedNotificationCenter.default().postNotificationName(
            fixtureCommand, object: nil,
            userInfo: userInfo,
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
        case .read(let options):
          let running = session ?? E2ESession(reader: reader)
          session = running
          let record = await running.press(options)
          rows.append(
            .read(ms: milliseconds(clock.now - start), session: record, report: reader.lastReport))
        case .write(let options):
          let running = session ?? E2ESession(reader: reader)
          session = running
          let record = await running.write(options)
          rows.append(
            .write(ms: milliseconds(clock.now - start), session: record, report: reader.lastReport))
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
  /// and, unless the step asks for the model, the translator (which echoes the text).
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
      /// The translation's timings and outcome, for steps that translate.
      var translationShownMs: Double?
      var firstTextMs: Double?
      var endedMs: Double?
      var textUpdates = 0
      /// States the panel actually took on; fewer than the updates when text was throttled.
      var panelStates = 0
      var lastState: PanelState?
      var secondPress: String?
      var escapeSentMs: Double?
      /// Panel calls the coordinator made after the panel was dismissed or hidden.
      var callsAfterDismissal = 0
      var visibleAtEnd = false
      /// `write` steps: the panel's state before Return, the toast, and the field's value
      /// after the replacement and after ⌘Z.
      var stateBeforeReturn: PanelState?
      var toast: ToastMessage?
      var valueAfterReplace: String?
      var valueAfterUndo: String?
      /// The field's formatting after each, as `describeRuns` writes it.
      var formattingAfterReplace: String?
      var formattingAfterUndo: String?
    }

    private let reader: AccessibilitySelectionReader
    private let controller = PanelController()
    private var options = E2EReadOptions()
    private var record = Record()
    private var dismissed = false
    private let clock = ContinuousClock()
    private var start = ContinuousClock.now
    private lazy var coordinator = SessionCoordinator(
      reader: self, panel: self,
      environment: SessionCoordinator.Environment(
        makeTranslator: { [unowned self] in self.translator() },
        languagePair: { LanguagePair() },
        refreshPermissions: {
          PermissionStatus(
            accessibility: AXIsProcessTrusted(), postEvent: CGPreflightPostEventAccess())
        },
        permissionNotice: { _ in PanelNotice(title: "permission") },
        performPermissionAction: { _ in false },
        openSettings: {},
        mouseLocation: { NSEvent.mouseLocation },
        makeProofreader: { [unowned self] in self.proofreader() },
        replaceWriter: SystemReplaceWriter(
          system: LiveReplaceSystem(queue: reader.queue, clipboard: reader.clipboard)),
        showToast: { [unowned self] message, _ in self.record.toast = message },
        lookUpTerm: { term, _ in [E2EStub.entry(term)] },
        makeCardMaker: { [unowned self] in self.cardMaker() },
        makeTranslateOut: { [unowned self] in self.translateOutEngine() }))

    init(reader: AccessibilitySelectionReader) {
      self.reader = reader
      controller.onDismiss = { [unowned self] in
        self.dismissed = true
        self.coordinator.panelDismissed($0)
      }
      controller.onConfirm = { [unowned self] in self.coordinator.confirm(anyway: $0) }
    }

    /// Presses the shortcut, waits for the session to finish, then hides the panel.
    func press(_ options: E2EReadOptions) async -> Record {
      self.options = options
      record = Record()
      dismissed = false
      start = clock.now
      let statesBefore = controller.shownStates
      let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
      coordinator.hotkeyPressed(.read)
      let extra = Task { await self.extraInput(options) }
      await coordinator.settle()
      record.endedMs = elapsed
      await extra.value
      // A second press may have started nothing, or ended the session; wait for either.
      await coordinator.settle()
      record.visibleAtEnd = controller.isVisible
      record.panelStates = controller.shownStates - statesBefore
      record.frontAppUnchanged =
        NSWorkspace.shared.frontmostApplication?.processIdentifier == front
      coordinator.end()
      // Let the target's window take key back before the next step.
      try? await Task.sleep(for: .milliseconds(100))
      return record
    }

    /// Presses the write shortcut and waits for the panel to finish, then presses Return in
    /// the panel, as the user would, and reads the field after the replacement and after ⌘Z.
    func write(_ options: E2EReadOptions) async -> Record {
      self.options = options
      record = Record()
      dismissed = false
      start = clock.now
      let statesBefore = controller.shownStates
      coordinator.hotkeyPressed(.write)
      await coordinator.settle()
      record.endedMs = elapsed
      // The panel applies states once per frame; Return is routed by the state it shows.
      for _ in 0..<40 where !controller.state.phase.canReplace {
        try? await Task.sleep(for: .milliseconds(25))
      }
      record.stateBeforeReturn = controller.state
      record.panelStates = controller.shownStates - statesBefore
      guard case .success(let selection) = record.result, let target = selection.target,
        controller.isVisible
      else {
        record.visibleAtEnd = controller.isVisible
        coordinator.end()
        return record
      }
      send(keyCode: PanelKeys.returnKey, characters: "\r", to: controller.window)
      await coordinator.settle()
      record.visibleAtEnd = controller.isVisible
      // The target's window takes key back once the panel is gone.
      try? await Task.sleep(for: .milliseconds(300))
      record.valueAfterReplace = AX.string(target.element.raw, kAXValueAttribute).1
      record.formattingAfterReplace = formatting(of: target.element)
      postCommandZ(to: target.app.pid)
      try? await Task.sleep(for: .milliseconds(500))
      record.valueAfterUndo = AX.string(target.element.raw, kAXValueAttribute).1
      record.formattingAfterUndo = formatting(of: target.element)
      coordinator.end()
      return record
    }

    private func send(keyCode: UInt16, characters: String, to window: NSWindow) {
      guard
        let event = NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: window.windowNumber, context: nil, characters: characters,
          charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
      else { return }
      window.sendEvent(event)
    }

    /// The whole field's formatting through accessibility, read the way a capture reads a
    /// selection's; nil when the field does not report it.
    private func formatting(of element: AXElement) -> String? {
      guard let value = AX.string(element.raw, kAXValueAttribute).1 else { return nil }
      let range = CFRange(location: 0, length: value.utf16.count)
      return readFormattedSelection(element.raw, range: range, text: value).map {
        describeRuns(styledRuns($0))
      }
    }

    /// ⌘Z to the app, as the user would press it: the app's own undo, not Dict's.
    private func postCommandZ(to pid: pid_t) {
      let z: CGKeyCode = 6
      for isDown in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: z, keyDown: isDown)
        event?.flags = .maskCommand
        event?.postToPid(pid)
      }
    }

    /// The second press and the Esc key the step asks for, at their times.
    private func extraInput(_ options: E2EReadOptions) async {
      if let ms = options.pressAgainAfterMs {
        try? await Task.sleep(until: start.advanced(by: .milliseconds(ms)), clock: clock)
        record.secondPress = controller.isVisible ? "panel visible" : "panel hidden"
        coordinator.hotkeyPressed(.read)
      }
      if let ms = options.escapeAfterMs {
        try? await Task.sleep(until: start.advanced(by: .milliseconds(ms)), clock: clock)
        guard
          let escape = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: controller.window.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: PanelKeys.escape)
        else { return }
        record.escapeSentMs = elapsed
        controller.window.sendEvent(escape)
      }
    }

    private var elapsed: Double { milliseconds(clock.now - start) }

    private func translator() -> any SessionTranslator {
      guard options.usesModel else { return self }
      var preferences = PreferencesStore(defaults: .standard).load().model
      if let baseURL = options.baseURL { preferences.baseURL = baseURL }
      var secrets: any SecretStore = CachedSecretStore.app
      if let key = options.apiKey, let provider = preferences.providerID {
        secrets = InMemorySecretStore([provider: key])
      }
      return makeTranslationEngine(
        preferences, presets: (try? ProviderPreset.all()) ?? [], secrets: secrets)
    }

    private func translateOutEngine() -> any SessionTranslateOut {
      guard options.usesModel else {
        return TranslateOutEngine(
          model: ModelTranslator(model: E2EStub.TranslateOutModel()),
          appleAvailability: { _, _ in .notInstalled })
      }
      return makeTranslateOutEngine(
        PreferencesStore(defaults: .standard).load().model,
        presets: (try? ProviderPreset.all()) ?? [], secrets: CachedSecretStore.app)
    }

    private func proofreader() -> (any SessionProofreader)? {
      guard options.usesModel else { return Proofreader(model: E2EStub.ProofreadModel()) }
      return makeProofreader(
        PreferencesStore(defaults: .standard).load().model,
        presets: (try? ProviderPreset.all()) ?? [], secrets: CachedSecretStore.app)
    }

    private func cardMaker() -> CardMaker? {
      guard options.usesModel else { return CardMaker(model: E2EStub.CardModel()) }
      var preferences = PreferencesStore(defaults: .standard).load().model
      if let baseURL = options.baseURL { preferences.baseURL = baseURL }
      var secrets: any SecretStore = CachedSecretStore.app
      if let key = options.apiKey, let provider = preferences.providerID {
        secrets = InMemorySecretStore([provider: key])
      }
      return makeCardMaker(
        preferences, presets: (try? ProviderPreset.all()) ?? [], secrets: secrets)
    }

    func capture(
      policy: ClipboardPolicy, beforeFallback: () -> Void
    ) async -> Result<Selection, CaptureFailure> {
      let showing = {
        beforeFallback()
        self.record.readingShownMs = self.elapsed
        self.record.keyAtShow = self.controller.window.isKeyWindow
      }
      let result =
        if let force = options.force {
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
      dismissed = false
      noteState(state, call: "show")
    }

    func update(_ state: PanelState) {
      if dismissed || !controller.isVisible { record.callsAfterDismissal += 1 }
      controller.update(state)
      noteState(state, call: "update")
    }

    private func noteState(_ state: PanelState, call: String) {
      let now = elapsed
      record.panelCalls.append(String(format: "%@:%@@%.1f", call, state.phase.name, now))
      record.lastState = state
      if case .generating = state.phase, record.translationShownMs == nil {
        record.translationShownMs = now
      }
      if state.phase.copyableText != nil {
        record.textUpdates += 1
        if record.firstTextMs == nil { record.firstTextMs = now }
      }
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

  /// The dictionary and card model of `read` steps: every term is in the dictionary as
  /// itself, and the card explains it in a fixed way, so a scenario checks the routing and
  /// the panel, not the data.
  enum E2EStub {
    static func entry(_ term: String) -> LexiconEntry {
      LexiconEntry(
        lemma: term, ipaUS: "/e2e/", ipaUK: "/e2e/", band: .common,
        senses: [LexiconSense(pos: "noun", gloss: "存根释义", source: "en")])
    }

    struct CardModel: TextModel {
      func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        let card = """
          {"status":"ok","lemma":"stub","phonetic":"","partOfSpeech":"noun",\
          "definition":"存根卡片","contextTranslation":"存根译文","otherSenses":[],\
          "examples":[],"collocations":[],"level":""}
          """
        return AsyncThrowingStream { continuation in
          continuation.yield(.text(card))
          continuation.yield(.finished(.complete, nil))
          continuation.finish()
        }
      }
    }
  }

  extension E2EStub {
    /// Translates out the scenarios' sentences, and translates any English back, the way the
    /// mock model does for the same sentences (`Fixtures/MockModel/replies.json`).
    struct TranslateOutModel: TextModel {
      static let translations = [
        "我们明天下午三点开会。": "We have a meeting at three tomorrow afternoon."
      ]

      func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        let isForward =
          request.user.contains("as the writer's own message")
          || request.system.contains("as the writer's own message")
        let reply =
          isForward
          ? Self.translations.first { request.user.contains($0.key) }?.value
            ?? "Stub translation."
          : Self.translations.first { request.user.contains($0.value) }?.key ?? "存根回译。"
        return AsyncThrowingStream { continuation in
          continuation.yield(.text(reply))
          continuation.yield(.finished(.complete, nil))
          continuation.finish()
        }
      }
    }
  }

  extension E2EStub {
    /// Corrects the scenarios' sentences with fixed edit lists; anything else has no
    /// mistakes.
    struct ProofreadModel: TextModel {
      static let edits = [
        "Ths is a bold wrd and a lnk here.": """
        {"edits":[{"kind":"spelling","wrong":"Ths","right":"This"},\
        {"kind":"spelling","wrong":"wrd","right":"word"},\
        {"kind":"spelling","wrong":"lnk","right":"link"},\
        {"kind":"spelling","wrong":"paragraf","right":"paragraph"}]}
        """
      ]

      func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        let reply =
          Self.edits.first { request.user.contains($0.key) }?.value ?? #"{"edits":[]}"#
        return AsyncThrowingStream { continuation in
          continuation.yield(.text(reply))
          continuation.yield(.finished(.complete, nil))
          continuation.finish()
        }
      }
    }
  }

  extension E2ESession.Record {
    /// The write part of a `write` row.
    var write: [String: Any] {
      var object: [String: Any] = ["visibleAtEnd": visibleAtEnd]
      object["phase"] = stateBeforeReturn?.phase.name ?? NSNull()
      object["result"] = stateBeforeReturn?.phase.copyableText ?? NSNull()
      if case .translatedOut(let translation) = stateBeforeReturn?.phase {
        switch translation.backTranslation {
        case .text(let text): object["backTranslation"] = text
        case .pending, .unavailable: object["backTranslation"] = NSNull()
        }
        object["issues"] = translation.issues.map { "\($0)" }
        object["replaceable"] = translation.replaceable
      }
      object["toast"] = toast.map { String(describing: $0) } ?? NSNull()
      object["valueAfterReplace"] = valueAfterReplace ?? NSNull()
      object["valueAfterUndo"] = valueAfterUndo ?? NSNull()
      object["formattingAfterReplace"] = formattingAfterReplace ?? NSNull()
      object["formattingAfterUndo"] = formattingAfterUndo ?? NSNull()
      return object
    }

    /// The translation's part of a `read` row.
    var translation: [String: Any] {
      var object: [String: Any] = [
        "textUpdates": textUpdates, "panelStates": panelStates,
        "callsAfterDismissal": callsAfterDismissal,
        "visibleAtEnd": visibleAtEnd,
      ]
      object["panelShownMs"] = translationShownMs.map(rounded) ?? NSNull()
      object["firstTextMs"] = firstTextMs.map(rounded) ?? NSNull()
      object["endedMs"] = endedMs.map(rounded) ?? NSNull()
      object["escapeSentMs"] = escapeSentMs.map(rounded) ?? NSNull()
      object["secondPress"] = secondPress ?? NSNull()
      object["phase"] = lastState?.phase.name ?? NSNull()
      if case .card(let card) = lastState?.phase {
        object["lemma"] = card.lemma
        object["cardModel"] = String(describing: card.model)
        object["definition"] = card.definition ?? NSNull()
      }
      object["result"] = lastState?.phase.copyableText ?? NSNull()
      object["note"] = lastState?.note?.text ?? NSNull()
      object["noteAction"] = lastState?.note?.action?.id ?? NSNull()
      switch lastState?.phase {
      case .failure(let notice), .needsSetup(let notice):
        object["noticeTitle"] = notice.title
        object["noticeMessage"] = notice.message ?? NSNull()
        object["noticeActions"] = notice.actions.map(\.id)
      default:
        break
      }
      return object
    }
  }
#endif
