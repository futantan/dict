// SPDX-License-Identifier: GPL-3.0-or-later
//
// Honest AppKit text controls: they behave like stock controls and only log the copy, paste
// and accessibility-write events they receive.

import AppKit

/// An `NSTextView` that logs copy, paste and accessibility writes. Also used as the window's
/// field editor for `NSTextField`, where the control is the editor's delegate.
final class LoggingTextView: NSTextView {
  var controlID: String {
    if isFieldEditor, let field = delegate as? NSView { return field.identifier?.rawValue ?? "" }
    return identifier?.rawValue ?? ""
  }

  private var selectedString: String {
    (string as NSString).substring(with: selectedRange())
  }

  override func copy(_ sender: Any?) {
    EventLog.shared.record(.copy, control: controlID, detail: selectedString)
    super.copy(sender)
  }

  override func paste(_ sender: Any?) {
    EventLog.shared.record(.paste, control: controlID, detail: pasteboardString)
    super.paste(sender)
  }

  override func pasteAsPlainText(_ sender: Any?) {
    EventLog.shared.record(.paste, control: controlID, detail: pasteboardString)
    super.pasteAsPlainText(sender)
  }

  override func setAccessibilitySelectedText(_ accessibilitySelectedText: String?) {
    EventLog.shared.record(
      .axWrite, control: controlID, detail: "selectedText=\(accessibilitySelectedText ?? "")")
    super.setAccessibilitySelectedText(accessibilitySelectedText)
  }

  override func setAccessibilityValue(_ accessibilityValue: Any?) {
    EventLog.shared.record(
      .axWrite, control: controlID, detail: "value=\(accessibilityValue as? String ?? "")")
    super.setAccessibilityValue(accessibilityValue)
  }

  private var pasteboardString: String { NSPasteboard.general.string(forType: .string) ?? "" }
}

/// Builds the scrollable text views and the single-line fields.
@MainActor
enum TextControls {
  static func textView(id: String, rich: Bool, text: String) -> (NSScrollView, LoggingTextView) {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    let textView = LoggingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 60))
    textView.identifier = NSUserInterfaceItemIdentifier(id)
    textView.setAccessibilityIdentifier(id)
    textView.isRichText = rich
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = false
    textView.minSize = .zero
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true
    setContent(text, of: textView)
    scroll.documentView = textView
    scroll.heightAnchor.constraint(equalToConstant: 60).isActive = true
    return (scroll, textView)
  }

  static func setContent(_ text: String, of textView: NSTextView) {
    let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    guard textView.isRichText else {
      textView.string = text
      textView.font = font
      return
    }
    // Rich text: bold the second word so the content really carries attributes.
    let attributed = NSMutableAttributedString(
      string: text, attributes: [.font: font, .foregroundColor: NSColor.textColor])
    let words = (text as NSString).components(separatedBy: " ")
    if words.count > 1 {
      let range = NSRange(location: words[0].utf16.count + 1, length: words[1].utf16.count)
      attributed.addAttribute(
        .font, value: NSFont.boldSystemFont(ofSize: font.pointSize), range: range)
    }
    textView.textStorage?.setAttributedString(attributed)
  }

  static func field(id: String, secure: Bool, text: String) -> NSTextField {
    let field = secure ? NSSecureTextField(string: text) : NSTextField(string: text)
    field.identifier = NSUserInterfaceItemIdentifier(id)
    field.setAccessibilityIdentifier(id)
    field.isEditable = true
    field.isSelectable = true
    return field
  }
}
