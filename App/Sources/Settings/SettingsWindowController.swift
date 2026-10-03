// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// The Settings window: a standard toolbar of tabs, each a SwiftUI pane. The window takes
/// the height of the selected pane.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  /// The window the status menu opens. M1.11 replaces `hotkeys` with the app's own
  /// `HotkeyCenter` before the window is first shown.
  static let shared = SettingsWindowController()

  let model: SettingsModel
  var hotkeys: HotkeyCenter

  private let tabs = SettingsTabViewController()

  init(model: SettingsModel = SettingsModel(), hotkeys: HotkeyCenter = HotkeyCenter()) {
    self.model = model
    self.hotkeys = hotkeys
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: SettingsPane.width, height: 300),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: true)
    window.toolbarStyle = .preference
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func show(_ pane: SettingsPane? = nil) {
    guard let window else { return }
    prepare()
    if let pane { select(pane) }
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }

  /// Builds the tabs once, sized to the first pane and centered, without showing the window.
  func prepare() {
    guard let window, tabs.tabViewItems.isEmpty else { return }
    tabs.tabStyle = .toolbar
    for pane in SettingsPane.allCases {
      let item = NSTabViewItem(viewController: hostingController(for: pane))
      item.label = pane.title
      item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
      tabs.addTabViewItem(item)
    }
    window.contentViewController = tabs
    tabs.fitWindow(animated: false)
    window.center()
  }

  func select(_ pane: SettingsPane) {
    guard let index = SettingsPane.allCases.firstIndex(of: pane) else { return }
    tabs.selectedTabViewItemIndex = index
  }

  private func hostingController(for pane: SettingsPane) -> NSViewController {
    let root: AnyView =
      switch pane {
      case .languages: AnyView(LanguagesPane(model: model))
      case .model: AnyView(ModelPane(model: model))
      case .shortcuts: AnyView(ShortcutsPane(center: hotkeys))
      }
    let controller = NSHostingController(rootView: root)
    controller.sizingOptions = [.preferredContentSize]
    controller.title = pane.title
    return controller
  }

  func windowWillClose(_ notification: Notification) {
    window?.makeFirstResponder(nil)
    model.commitKey()
  }
}

/// Resizes the window to the selected pane, keeping its top edge in place.
private final class SettingsTabViewController: NSTabViewController {
  override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
    super.tabView(tabView, didSelect: tabViewItem)
    fitWindow(animated: view.window?.isVisible == true)
  }

  override func preferredContentSizeDidChange(for viewController: NSViewController) {
    super.preferredContentSizeDidChange(for: viewController)
    guard viewController === tabViewItems[safe: selectedTabViewItemIndex]?.viewController else {
      return
    }
    fitWindow(animated: false)
  }

  func fitWindow(animated: Bool) {
    guard let window = view.window,
      let child = tabViewItems[safe: selectedTabViewItemIndex]?.viewController
    else { return }
    window.title = child.title ?? ""
    let size = child.preferredContentSize
    guard size.height > 0 else { return }
    var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
    frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
    window.setFrame(frame, display: true, animate: animated)
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

extension AppDelegate {
  /// The status menu's Settings item; reached through the responder chain like About.
  @objc func showSettings(_ sender: Any?) {
    SettingsWindowController.shared.show()
  }
}
