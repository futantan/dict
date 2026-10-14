// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import DictCore

/// Timings and the path taken by one capture, for the log and the e2e result.
struct CaptureReport: Sendable {
  var bundleID: String?
  var kind: AppKind?
  var warmup: WarmupState?
  var attempts = 0
  var firstStageMs: Double?
  var secondStageMs: Double?
  var fallbackMs: Double?
  /// From triggering the copy to the clipboard change; nil when no copy landed.
  var copyWaitMs: Double?
  var totalMs = 0.0
}

/// What the accessibility queue job returns: the first stage and, on success, the second.
struct AccessibilityRead: Sendable {
  let outcome: Result<String, CaptureFailure>
  let bounds: CGRect?
  let context: ContextSentence?
  /// The field, when the selection may be replaced (architecture 4.3).
  let target: ReplaceSnapshot?
  /// The selection's formatting, when the field may be replaced (architecture 4.7).
  var rich: RichSource? = nil
  let attempts: Int
  let firstStage: Duration
  let secondStage: Duration?
}

/// Reads the front app's selection (architecture 3): accessibility first, then on the hotkey
/// path the menu bar Copy item, then ⌘C posted to the app.
@MainActor
final class AccessibilitySelectionReader: SelectionReader {
  let warmer: AccessibilityWarmer
  private(set) var lastReport = CaptureReport()
  /// The one accessibility queue; replacing uses it too.
  let queue: AXQueue
  let clipboard: ClipboardGateway
  private let resolver: TargetAppResolver
  private var copyItems: [TargetApp.InstanceKey: AXElement] = [:]

  init(queue: AXQueue = AXQueue(), clipboard: ClipboardGateway = ClipboardGateway()) {
    let resolver = TargetAppResolver()
    self.queue = queue
    self.clipboard = clipboard
    self.resolver = resolver
    self.warmer = AccessibilityWarmer(queue: queue, resolver: resolver)
  }

  /// Starts warming Chromium and Electron apps as they come to the front.
  func start() { warmer.start() }

  func capture(
    policy: ClipboardPolicy, beforeFallback: () -> Void
  ) async -> Result<Selection, CaptureFailure> {
    let clock = ContinuousClock()
    let start = clock.now
    var report = CaptureReport()
    let result = await capture(policy: policy, beforeFallback: beforeFallback, report: &report)
    report.totalMs = milliseconds(clock.now - start)
    lastReport = report
    log(result, report)
    return result
  }

  private func capture(
    policy: ClipboardPolicy, beforeFallback: () -> Void, report: inout CaptureReport
  ) async -> Result<Selection, CaptureFailure> {
    guard AXIsProcessTrusted() else { return .failure(.noAccessibilityPermission) }
    guard let front = NSWorkspace.shared.frontmostApplication else {
      return .failure(.unreadable(axError: nil))
    }
    let app = resolver.resolve(front)
    report.bundleID = app.bundleID
    report.kind = app.kind
    if app.kind == .ownApp { return .failure(.ownApp) }

    // A tree switched on just now, or not allowed on, is not worth the 150 ms wait.
    let warmup = await warmer.warm(app)
    report.warmup = warmup
    let treeOff =
      warmup == .justEnabled
      || (warmup == .notNeeded && (app.kind == .chromium || app.kind == .electron))

    var firstFailure = CaptureFailure.unreadable(axError: nil)
    if !treeOff {
      let read = await readAccessibility(app)
      report.attempts = read.attempts
      report.firstStageMs = milliseconds(read.firstStage)
      report.secondStageMs = read.secondStage.map(milliseconds)
      switch read.outcome {
      case .success(let text):
        let target = read.target.map {
          ReplaceTarget(
            app: app, element: $0.element, range: $0.range, selectedText: text,
            valueBefore: $0.valueBefore, axWritable: $0.axWritable)
        }
        return .success(
          Selection(
            text: text, source: .accessibility, app: app, bounds: read.bounds,
            context: read.context, target: target, rich: target == nil ? nil : read.rich))
      case .failure(let failure):
        firstFailure = failure
      }
    }

    guard needsCopyFallback(after: firstFailure, kind: app.kind, policy: policy) else {
      return .failure(firstFailure)
    }
    beforeFallback()
    let clock = ContinuousClock()
    let fallbackStart = clock.now
    defer { report.fallbackMs = milliseconds(clock.now - fallbackStart) }
    let run = await copyFallback(for: app).run(
      after: firstFailure, accessDenied: clipboard.isAccessDenied)
    report.copyWaitMs = run.copyWait.map(milliseconds)
    return run.result.map { copied in
      Selection(
        text: copied.text, source: copied.source, app: app, bounds: nil, context: nil,
        target: nil, rich: copied.rich)
    }
  }

  private func readAccessibility(_ app: TargetApp) async -> AccessibilityRead {
    let screens = NSScreen.screens.map(\.frame)
    let pid = app.pid
    let kind = app.kind
    return await queue.run { readSelection(pid: pid, kind: kind, screens: screens) }
  }

  /// `useMenu: false` skips the menu bar Copy item, for the e2e probe of the ⌘C path.
  private func copyFallback(for app: TargetApp, useMenu: Bool = true) -> CopyFallback {
    CopyFallback(
      clipboard: clipboard,
      findMenuCopy: { useMenu ? await self.findMenuCopy(app) : .notFound },
      pressMenuCopy: { await self.pressMenuCopy(app) },
      canPostEvents: { AXIsProcessTrusted() && CGPreflightPostEventAccess() },
      secureInputBlock: {
        let state = currentSecureInput()
        guard blocksKeyPosting(state, targetPID: app.pid, kind: app.kind) else { return nil }
        return .secureInput(holder: state.holderPID.flatMap(appName(pid:)))
      },
      postCopyKey: { postCopyKey(to: app.pid) })
  }

  /// Finds the Copy item, reusing the one cached for this app instance while it stays valid.
  private func findMenuCopy(_ app: TargetApp) async -> MenuCopyState {
    let cached = copyItems[app.instanceKey]
    let pid = app.pid
    let (state, item) = await queue.run { () -> (MenuCopyState, AXElement?) in
      if let cached, let state = copyMenuItemState(cached.raw) { return (state, cached) }
      guard let item = findCopyMenuItem(app: AX.application(pid)) else { return (.notFound, nil) }
      return (copyMenuItemState(item) ?? .notFound, AXElement(raw: item))
    }
    copyItems[app.instanceKey] = item
    return state
  }

  private func pressMenuCopy(_ app: TargetApp) async -> Int32? {
    guard let item = copyItems[app.instanceKey] else { return AXError.invalidUIElement.rawValue }
    let error = await queue.run { AX.press(item.raw) }
    return error == .success ? nil : error.rawValue
  }

  private func log(_ result: Result<Selection, CaptureFailure>, _ report: CaptureReport) {
    let path: String
    switch result {
    case .success(let selection): path = selection.source.caseName
    case .failure(let failure): path = "failed:\(failure.logDescription)"
    }
    let kind = report.kind.map { "\($0)" } ?? "-"
    let warmup = report.warmup.map { "\($0)" } ?? "-"
    Log.capture.info(
      """
      capture \(path, privacy: .public) app=\(report.bundleID ?? "-", privacy: .public) \
      kind=\(kind, privacy: .public) warmup=\(warmup, privacy: .public) \
      attempts=\(report.attempts, privacy: .public) \
      first=\(report.firstStageMs ?? -1, format: .fixed(precision: 1), privacy: .public)ms \
      second=\(report.secondStageMs ?? -1, format: .fixed(precision: 1), privacy: .public)ms \
      fallback=\(report.fallbackMs ?? -1, format: .fixed(precision: 1), privacy: .public)ms \
      copyWait=\(report.copyWaitMs ?? -1, format: .fixed(precision: 1), privacy: .public)ms \
      total=\(report.totalMs, format: .fixed(precision: 1), privacy: .public)ms
      """)
  }
}

#if DEBUG
  /// The copy path the e2e entry point forces, to measure it in apps whose selection
  /// accessibility reads (architecture 14.2).
  enum ForcedCopy: String, Sendable {
    case menu, key
  }

  extension AccessibilitySelectionReader {
    /// Skips the accessibility read and runs the copy fallback on the front app, through the
    /// menu bar Copy item or straight to ⌘C. `beforeCopying` runs first, as in `capture`.
    func captureByCopying(
      _ via: ForcedCopy, beforeCopying: () -> Void = {}
    ) async -> Result<Selection, CaptureFailure> {
      let clock = ContinuousClock()
      let start = clock.now
      var report = CaptureReport()
      defer {
        report.totalMs = milliseconds(clock.now - start)
        lastReport = report
      }
      guard let front = NSWorkspace.shared.frontmostApplication else {
        return .failure(.unreadable(axError: nil))
      }
      let app = resolver.resolve(front)
      report.bundleID = app.bundleID
      report.kind = app.kind
      beforeCopying()
      let run = await copyFallback(for: app, useMenu: via == .menu).run(
        after: .unreadable(axError: nil), accessDenied: clipboard.isAccessDenied)
      report.fallbackMs = milliseconds(clock.now - start)
      report.copyWaitMs = run.copyWait.map(milliseconds)
      return run.result.map {
        Selection(
          text: $0.text, source: $0.source, app: app, bounds: nil, context: nil, target: nil,
          rich: $0.rich)
      }
    }
  }
#endif

/// Both stages of the accessibility read (architecture 3.4, 3.5). Accessibility queue only.
/// The first stage has 150 ms in all; the second, best effort, another 100 ms, and a field it
/// misses stays nil. The replace snapshot is always taken: the Write key cannot work without
/// it, and it costs a few attribute reads.
func readSelection(pid: pid_t, kind: AppKind, screens: [CGRect]) -> AccessibilityRead {
  let clock = ContinuousClock()
  let start = clock.now
  let element = AX.application(pid)
  var attempts = 0
  let outcome = pollFirstStage(
    deadline: .milliseconds(150), interval: .milliseconds(10),
    elapsed: { clock.now - start },
    sleep: { Thread.sleep(forTimeInterval: milliseconds($0) / 1000) },
    attempt: {
      attempts += 1
      return readSelectionAttempt(app: element)
    })
  let firstStage = clock.now - start

  switch outcome {
  case .failed(let failure):
    return AccessibilityRead(
      outcome: .failure(failure), bounds: nil, context: nil, target: nil, attempts: attempts,
      firstStage: firstStage, secondStage: nil)
  case .found(let found):
    let secondStart = clock.now
    let bounds = readSelectionRect(found).flatMap {
      selectionBounds(fromAccessibility: $0, screens: screens)
    }
    let context =
      clock.now - secondStart < .milliseconds(100) ? readContext(found, kind: kind) : nil
    let target = replaceSnapshot(found, kind: kind)
    // Only native apps report formatting through accessibility in full (architecture 4.7).
    let rich =
      target != nil && kind == .native
      ? found.range.flatMap { readFormattedSelection(found.element, range: $0, text: found.text) }
      : nil
    return AccessibilityRead(
      outcome: .success(found.text), bounds: bounds, context: context, target: target,
      rich: rich.map(RichSource.accessibility), attempts: attempts,
      firstStage: firstStage, secondStage: clock.now - secondStart)
  }
}

func milliseconds(_ duration: Duration) -> Double {
  let (seconds, attoseconds) = duration.components
  return Double(seconds) * 1000 + Double(attoseconds) / 1e15
}

extension CaptureSource {
  var caseName: String {
    switch self {
    case .accessibility: "accessibility"
    case .menuCopy: "menuCopy"
    case .keyCopy: "keyCopy"
    case .ocr: "ocr"
    case .typed: "typed"
    }
  }
}

extension CaptureFailure {
  var caseName: String {
    switch self {
    case .noAccessibilityPermission: "noAccessibilityPermission"
    case .noPostEventPermission: "noPostEventPermission"
    case .secureField: "secureField"
    case .secureInput: "secureInput"
    case .clipboardDenied: "clipboardDenied"
    case .ownApp: "ownApp"
    case .nothingSelected: "nothingSelected"
    case .unreadable: "unreadable"
    }
  }

  /// The case name plus non-user details (an error code or app name), never the field text.
  var logDescription: String {
    switch self {
    case .unreadable(let code): "unreadable(\(code.map(String.init) ?? "nil"))"
    case .secureInput(let holder): "secureInput(\(holder ?? "unknown"))"
    default: caseName
    }
  }
}
