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
    if textView.identifier?.rawValue == ControlID.formattedTextView {
      textView.textStorage?.setAttributedString(formatted(text, font: font))
      // ⌘Z after a replacement must undo exactly that.
      textView.undoManager?.removeAllActions()
      return
    }
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

  /// Light markup as formatted text: `**bold**` and `[text](url)`, nothing else.
  static func formatted(_ markup: String, font: NSFont) -> NSAttributedString {
    let result = NSMutableAttributedString()
    var bold = false
    var rest = Substring(markup)
    func append(_ text: some StringProtocol, link: URL? = nil) {
      var attributes: [NSAttributedString.Key: Any] = [
        .font: bold ? NSFont.boldSystemFont(ofSize: font.pointSize) : font,
        .foregroundColor: NSColor.textColor,
      ]
      attributes[.link] = link
      result.append(NSAttributedString(string: String(text), attributes: attributes))
    }
    while let next = rest.firstIndex(where: { $0 == "*" || $0 == "[" }) {
      append(rest[..<next])
      rest = rest[next...]
      if rest.hasPrefix("**") {
        bold.toggle()
        rest = rest.dropFirst(2)
      } else if let close = rest.firstIndex(of: "]"),
        rest[rest.index(after: close)...].hasPrefix("("),
        let end = rest[close...].firstIndex(of: ")")
      {
        let label = rest[rest.index(after: rest.startIndex)..<close]
        let url = rest[rest.index(close, offsetBy: 2)..<end]
        append(label, link: URL(string: String(url)))
        rest = rest[rest.index(after: end)...]
      } else {
        append(rest.prefix(1))
        rest = rest.dropFirst()
      }
    }
    append(rest)
    return result
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
