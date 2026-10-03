// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// The first-run window (architecture 11.4). It is a normal window that activates Dict, so
/// the system's prompts for Accessibility and translation downloads have a window to attach
/// to. Closing it before Done brings it back on the next launch.
@MainActor
final class OnboardingWindowController: NSWindowController {
  let model: OnboardingModel

  init(model: OnboardingModel, appName: String) {
    self.model = model
    let hosting = NSHostingController(rootView: OnboardingView(model: model, appName: appName))
    hosting.sizingOptions = [.preferredContentSize]
    let window = NSWindow(contentViewController: hosting)
    window.styleMask = [.titled, .closable]
    window.title = String(
      localized: "Welcome to \(appName)",
      comment: "Title of the first-run window; the argument is the app name")
    window.isReleasedWhenClosed = false
    super.init(window: window)
    model.finish = { [weak self] in self?.close() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func show(_ step: OnboardingStep? = nil) {
    guard let window else { return }
    if let step { model.step = step }
    if !window.isVisible { window.center() }
    window.makeKeyAndOrderFront(nil)
    NSApp.activateFromFrontApp()
  }
}
