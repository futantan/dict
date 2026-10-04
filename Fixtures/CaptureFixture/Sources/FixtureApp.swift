// SPDX-License-Identifier: GPL-3.0-or-later
//
// End-to-end test fixture (architecture 14.3). One window holds every control, each with a
// stable accessibility identifier. A driver selects text through the distributed-notification
// command channel and reads the copy, paste and write events from the `--log` JSON Lines file.
// M1 has only honest controls; the lying ones arrive with M3.5.

import AppKit

@main
@MainActor
final class FixtureApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var window: NSWindow?
  private var textViews: [String: LoggingTextView] = [:]
  private var fields: [String: NSTextField] = [:]
  private var customViews: [String: CustomTextView] = [:]
  private var web: WebControls?
  private let fieldEditor = LoggingTextView()

  static func main() {
    let app = NSApplication.shared
    let delegate = FixtureApp()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = Self.mainMenu()
    fieldEditor.isFieldEditor = true

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 6
    stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

    for (id, rich, text) in [
      (ControlID.plainTextView, false, "The quick brown fox jumps over the lazy dog."),
      (ControlID.richTextView, true, "Sphinx of black quartz, judge my vow."),
    ] {
      let (scroll, textView) = TextControls.textView(id: id, rich: rich, text: text)
      textViews[id] = textView
      add(scroll, label: id, to: stack)
    }
    for (id, secure, text) in [
      (ControlID.textField, false, "Pack my box with five dozen liquor jugs."),
      (ControlID.secureField, true, "correct horse battery staple"),
    ] {
      let field = TextControls.field(id: id, secure: secure, text: text)
      fields[id] = field
      add(field, label: id, to: stack)
    }
    let web = WebControls { [weak self] in self?.didLoadWebPage() }
    self.web = web
    add(web.webView, label: "web.*", to: stack)
    for (id, behavior, text) in [
      (
        ControlID.customNoSelectedText, CustomTextView.Behavior.noSelectedText,
        "Jackdaws love my big sphinx of quartz."
      ),
      (ControlID.customEmpty, .empty, "Nothing here can be selected."),
      (ControlID.customCopiesLine, .copiesLine, "let first = 1\nlet second = 2"),
    ] {
      let view = CustomTextView(id: id, behavior: behavior, content: text)
      customViews[id] = view
      add(view, label: id, to: stack)
    }

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 820),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
      defer: false)
    window.title = "CaptureFixture"
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentView = stack
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApp.activate()

    // Deliver commands even while another app is active; AppKit suspends delivery otherwise.
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(didReceiveCommand(_:)), name: FixtureCommand.notificationName,
      object: nil, suspensionBehavior: .deliverImmediately)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
    guard let field = client as? NSTextField, !(field is NSSecureTextField) else { return nil }
    return fieldEditor
  }

  private func didLoadWebPage() {
    EventLog.shared.record(
      .ready, control: "app", detail: String(ProcessInfo.processInfo.processIdentifier))
  }

  @objc private func didReceiveCommand(_ notification: Notification) {
    guard let command = FixtureCommand(userInfo: notification.userInfo) else {
      EventLog.shared.record(.select, control: "", detail: "error: malformed command")
      return
    }
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate()
    select(command) { detail in
      Self.validateMenus()
      EventLog.shared.record(.select, control: command.control, detail: detail)
    }
  }

  /// A selection made by a command arrives without a user event, and AppKit revalidates the
  /// menu bar at most about once a second: an accessibility read of Copy right after a
  /// previous capture read it still saw the old state up to ~1 s later (measured 2026-10-04).
  /// A person selecting text and then pressing the hotkey gives AppKit that time.
  private static func validateMenus() {
    NSApp.mainMenu?.items.compactMap(\.submenu).forEach { $0.update() }
  }

  /// Applies a select command; calls back with the selected text or "error: …".
  private func select(_ command: FixtureCommand, completion: @escaping (String) -> Void) {
    let id = command.control
    if let textView = textViews[id] {
      if let content = command.content { TextControls.setContent(content, of: textView) }
      guard let range = selectionRange(of: command.text, in: textView.string) else {
        return completion("error: text not found")
      }
      window?.makeFirstResponder(textView)
      textView.setSelectedRange(range)
      textView.scrollRangeToVisible(range)
      completion((textView.string as NSString).substring(with: range))
    } else if let field = fields[id] {
      if let content = command.content { field.stringValue = content }
      guard let range = selectionRange(of: command.text, in: field.stringValue) else {
        return completion("error: text not found")
      }
      window?.makeFirstResponder(field)
      field.currentEditor()?.selectedRange = range
      completion((field.stringValue as NSString).substring(with: range))
    } else if let view = customViews[id] {
      guard let range = selectionRange(of: command.text, in: command.content ?? view.content)
      else { return completion("error: text not found") }
      view.select(range, content: command.content)
      window?.makeFirstResponder(view)
      completion((view.content as NSString).substring(with: view.selection))
    } else if let web, ControlID.web.contains(id) {
      web.select(command, completion: completion)
    } else {
      completion("error: unknown control \(id)")
    }
  }

  private func add(_ view: NSView, label: String, to stack: NSStackView) {
    let title = NSTextField(labelWithString: label)
    title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
    title.textColor = .secondaryLabelColor
    stack.addArrangedSubview(title)
    stack.addArrangedSubview(view)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
  }

  /// App and Edit menus. Captures find Copy by its ⌘C key equivalent (architecture 3.6).
  private static func mainMenu() -> NSMenu {
    let main = NSMenu()
    let appMenu = NSMenu()
    appMenu.addItem(
      withTitle: "Quit CaptureFixture", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    main.addItem(withTitle: "CaptureFixture", action: nil, keyEquivalent: "").submenu = appMenu

    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(
      withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
    return main
  }
}
