// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Shows, updates and hides the result panel (architecture 11.1). The session coordinator
/// (M1.11) uses only `show`, `update` and `hide`, and listens to the callbacks.
@MainActor
final class PanelController {
  /// The panel hid itself. Hiding ends the session: cancel whatever is in flight. Not
  /// called for `hide()`.
  var onDismiss: (PanelDismissal) -> Void = { _ in }
  /// The user pressed Return in the input field; the text is trimmed and non-empty.
  var onSubmit: (String) -> Void = { _ in }
  /// The user clicked a notice button; the value is `PanelAction.id`.
  var onAction: (PanelAction.ID) -> Void = { _ in }

  private let model = PanelModel()
  private lazy var panel = makePanel()
  private var anchor = PanelAnchor.none
  private var side = PanelSide.below
  private var contentHeight: CGFloat = 0
  private var mouseMonitor: Any?
  private var activationObserver: (any NSObjectProtocol)?
  /// Set before the window is ordered in and cleared before it is ordered out, so callbacks
  /// fired during either see the session's state, not the window's.
  private(set) var isVisible = false

  var state: PanelState { model.state }
  /// The panel window, for tests and for anchoring other windows to it.
  var window: NSPanel { panel }

  /// Shows the panel with `state` next to `anchor` and makes it key without activating Dict.
  func show(_ state: PanelState, near anchor: PanelAnchor) {
    self.anchor = anchor
    side = .below
    model.draft = ""
    model.presentation += 1
    model.state = state
    layOut()
    isVisible = true
    panel.makeKeyAndOrderFront(nil)
    installMonitors()
    Log.ui.info("panel shown: \(state.phase.name, privacy: .public)")
  }

  /// Replaces what the panel shows; the panel stays where it is and grows away from its
  /// anchor. Does nothing while the panel is hidden.
  func update(_ state: PanelState) {
    guard isVisible, model.state != state else { return }
    if model.state.phase.name != state.phase.name {
      Log.ui.info("panel state: \(state.phase.name, privacy: .public)")
    }
    model.state = state
  }

  /// Hides the panel without calling `onDismiss`.
  func hide() {
    guard isVisible else { return }
    isVisible = false
    removeMonitors()
    panel.orderOut(nil)
    Log.ui.info("panel hidden")
  }

  // MARK: - Window

  private func makePanel() -> ResultPanel {
    let view = PanelView(
      model: model,
      onSubmit: { [weak self] in self?.onSubmit($0) },
      onAction: { [weak self] in self?.onAction($0) },
      onContentHeight: { [weak self] in self?.contentHeightChanged($0) })
    let hosting = NSHostingView(rootView: view)
    hosting.sizingOptions = []
    let panel = ResultPanel(content: hosting)
    panel.onEscape = { [weak self] in self?.dismiss(.escape) }
    panel.copyableText = { [weak self] in self?.model.state.phase.copyableText }
    return panel
  }

  private func contentHeightChanged(_ height: CGFloat) {
    let height = height.rounded(.up)
    guard height != contentHeight else { return }
    contentHeight = height
    if isVisible { layOut() }
  }

  /// Sizes and places the panel for the current content height. SwiftUI reports the
  /// height during layout, so laying out the content first gives the right size before the
  /// panel is shown.
  private func layOut() {
    panel.contentView?.layoutSubtreeIfNeeded()
    guard
      let placement = PanelLayout.place(
        contentHeight: contentHeight, anchor: anchor, screens: Self.currentScreens(),
        preferredSide: side)
    else { return }
    side = placement.side
    model.isScrollable = placement.frame.height < contentHeight
    if panel.frame != placement.frame {
      panel.setFrame(placement.frame, display: isVisible)
      panel.invalidateShadow()
    }
  }

  private func dismiss(_ reason: PanelDismissal) {
    guard isVisible else { return }
    hide()
    Log.ui.info("panel dismissed: \(String(describing: reason), privacy: .public)")
    onDismiss(reason)
  }

  // MARK: - Clicks outside and app switches

  /// Installed only while the panel is visible.
  ///
  /// A global mouse monitor sees clicks in other apps only, which is exactly "outside the
  /// panel". App activation covers ⌘Tab. Losing key status is deliberately not a trigger:
  /// the clipboard fallback presses the target's Copy menu item or posts ⌘C to it while the
  /// panel shows "reading", and must not end the session if that moves key focus.
  private func installMonitors() {
    guard mouseMonitor == nil else { return }
    mouseMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.dismiss(.clickOutside) }
    }
    activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.dismiss(.appSwitched) }
    }
  }

  private func removeMonitors() {
    if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    if let activationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
    }
    mouseMonitor = nil
    activationObserver = nil
  }

  private static func currentScreens() -> [PanelScreen] {
    NSScreen.screens.map { PanelScreen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
  }
}

extension PanelPhase {
  /// The case name, for logs; never the text.
  var name: String {
    switch self {
    case .input: "input"
    case .reading: "reading"
    case .generating: "generating"
    case .result: "result"
    case .failure: "failure"
    case .needsSetup: "needsSetup"
    }
  }
}
