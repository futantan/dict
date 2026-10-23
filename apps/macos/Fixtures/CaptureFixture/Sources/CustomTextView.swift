// SPDX-License-Identifier: GPL-3.0-or-later
//
// A self-drawn text view, like an editor that does its own text rendering. To accessibility it
// is a plain group: it exposes neither its value nor its selected text, so reading it ends in
// "unreadable" and a capture has to fall back to the menu bar Copy item (architecture 3.6).

import AppKit

final class CustomTextView: NSView, NSMenuItemValidation {
  enum Behavior {
    /// Has a selection that only Copy can reveal.
    case noSelectedText
    /// Never has a selection; Copy is disabled.
    case empty
    /// No selection; Copy copies the caret's whole line, newline included, like code editors.
    case copiesLine
  }

  let behavior: Behavior
  private(set) var content: String
  private(set) var selection = NSRange(location: 0, length: 0)

  init(id: String, behavior: Behavior, content: String) {
    self.behavior = behavior
    self.content = content
    super.init(frame: .zero)
    identifier = NSUserInterfaceItemIdentifier(id)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(id)
    setAccessibilityLabel("Custom text")
    heightAnchor.constraint(equalToConstant: 44).isActive = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("not used") }

  private var controlID: String { identifier?.rawValue ?? "" }

  /// Places the selection on `range`. Views without selections keep only a caret there.
  func select(_ range: NSRange, content newContent: String?) {
    if let newContent { content = newContent }
    selection =
      behavior == .noSelectedText ? range : NSRange(location: range.location, length: 0)
    needsDisplay = true
  }

  /// What Copy puts on the clipboard; nil when there is nothing to copy.
  var copiedText: String? {
    let text = content as NSString
    switch behavior {
    case .noSelectedText:
      return selection.length > 0 ? text.substring(with: selection) : nil
    case .empty:
      return nil
    case .copiesLine:
      let line = text.substring(with: text.lineRange(for: selection))
      return line.hasSuffix("\n") ? line : line + "\n"
    }
  }

  override var acceptsFirstResponder: Bool { true }

  override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

  @objc func copy(_ sender: Any?) {
    EventLog.shared.record(.copy, control: controlID, detail: copiedText ?? "")
    guard let text = copiedText else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    menuItem.action == #selector(copy(_:)) ? copiedText != nil : false
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.textBackgroundColor.setFill()
    bounds.fill()
    let focused = window?.firstResponder === self
    (focused ? NSColor.keyboardFocusIndicatorColor : NSColor.separatorColor).setStroke()
    NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()

    let text = NSMutableAttributedString(
      string: content,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor.textColor,
      ])
    if selection.length > 0 {
      text.addAttribute(
        .backgroundColor, value: NSColor.selectedTextBackgroundColor, range: selection)
    }
    text.draw(in: bounds.insetBy(dx: 6, dy: 4))
  }
}
