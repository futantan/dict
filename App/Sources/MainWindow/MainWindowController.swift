// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// The main window (Design/main-app/README.md): the sidebar and the pages, under a
/// transparent title bar whose traffic lights sit inset in the sidebar.
///
/// Closing it only hides it; the app keeps running unless the user turned that off, which
/// `onClose` handles. It refreshes the log's snapshot whenever it becomes key.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
  let context: MainWindowContext
  /// Called after the window closed.
  var onClose: () -> Void = {}

  init(context: MainWindowContext) {
    self.context = context
    let hosting = NSHostingController(rootView: MainWindowView(context: context))
    hosting.sizingOptions = []
    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: WindowLayout.defaultSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: true)
    window.contentViewController = hosting
    window.setContentSize(WindowLayout.defaultSize)
    window.contentMinSize = WindowLayout.minimumSize
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
    // An empty unified toolbar makes the title bar as tall as the sidebar's top margin and
    // insets the traffic lights into it.
    let toolbar = NSToolbar(identifier: "main")
    window.toolbar = toolbar
    window.toolbarStyle = .unified
    window.isReleasedWhenClosed = false
    window.center()
    // Where the user left it last time, if anywhere.
    window.setFrameUsingName(Self.frameName)
    window.setFrameAutosaveName(Self.frameName)
    super.init(window: window)
    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Shows the window on `section`, or where it was, and makes Dict the active app.
  func show(_ section: MainSection? = nil) {
    if let section { context.navigation.section = section }
    present()
  }

  /// Shows the settings page scrolled to `section`.
  func show(settings section: SettingsSection) {
    context.navigation.show(section)
    present()
  }

  private static let frameName = "MainWindow"

  private func present() {
    window?.makeKeyAndOrderFront(nil)
    NSApp.activateFromFrontApp()
  }

  /// The search field's rect, in screen coordinates, for placing the result panel.
  func screenRect(ofContentRect rect: CGRect) -> CGRect? {
    guard let window, let view = window.contentView else { return nil }
    var frame = rect
    if !view.isFlipped { frame.origin.y = view.bounds.height - rect.maxY }
    return window.convertToScreen(view.convert(frame, to: nil))
  }

  func windowDidBecomeKey(_ notification: Notification) {
    Task { await context.data.refresh() }
  }

  func windowWillClose(_ notification: Notification) {
    window?.makeFirstResponder(nil)
    context.settings.commitKey()
    onClose()
  }
}
