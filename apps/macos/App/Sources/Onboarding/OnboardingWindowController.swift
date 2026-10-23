// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// The first-run window (architecture 11.4). It is a normal window that activates Dict, so
/// the system's Accessibility prompt has a window to attach to. Closing it before Done brings
/// it back on the next launch.
///
/// While it shows the accessibility step without the permission, it reads the permission
/// once a second: the system's change notification is not reliable enough on its own.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
  let model: OnboardingModel
  /// Reads the permissions; a change reaches `model.permissionsChanged` through the monitor.
  private let refreshPermissions: () -> Void
  private var poll: Timer?
  private let focus = FocusReturn()

  init(model: OnboardingModel, appName: String, refreshPermissions: @escaping () -> Void) {
    self.model = model
    self.refreshPermissions = refreshPermissions
    let hosting = NSHostingController(rootView: OnboardingView(model: model, appName: appName))
    hosting.sizingOptions = [.preferredContentSize]
    let window = NSWindow(contentViewController: hosting)
    window.styleMask = [.titled, .closable]
    window.title = String(
      localized: "Welcome to \(appName)",
      comment: "Title of the first-run window; the argument is the app name")
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.delegate = self
    model.finish = { [weak self] in self?.close() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func show() {
    guard let window else { return }
    if !window.isVisible { window.center() }
    focus.remember()
    window.makeKeyAndOrderFront(nil)
    NSApp.activateFromFrontApp()
    startPolling()
  }

  /// The sample's place on screen, for the result panel.
  func sampleAnchor() -> PanelAnchor {
    guard let view = window?.contentView, let window, model.sampleFrame != .zero else {
      return .mouse(NSEvent.mouseLocation)
    }
    var frame = model.sampleFrame
    if !view.isFlipped { frame.origin.y = view.bounds.height - frame.maxY }
    return .selection(window.convertToScreen(view.convert(frame, to: nil)))
  }

  func windowWillClose(_ notification: Notification) {
    poll?.invalidate()
    poll = nil
    if let window { focus.restore(closing: window) }
  }

  private func startPolling() {
    guard poll == nil else { return }
    poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.model.needsPermissionPolling else { return }
        self.refreshPermissions()
      }
    }
  }
}
