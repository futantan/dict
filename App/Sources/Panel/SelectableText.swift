// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Read-only, selectable text in an `NSTextView`.
///
/// SwiftUI's `.textSelection(.enabled)` keeps its selection in a text field that never
/// becomes the window's first responder, so the panel could not tell that part of the text
/// was selected and ⌘C copied the whole result. A text view becomes first responder when
/// clicked, and `ResultPanel` copies its selection (architecture 11.5).
struct SelectableText: NSViewRepresentable {
  let text: String
  let font: NSFont
  var color: NSColor = .labelColor
  var lineSpacing: CGFloat = 0
  /// 0 shows every line; otherwise the text is cut off with an ellipsis after this many.
  var maximumLines = 0
  var accessibilityLabel: String?

  func makeNSView(context: Context) -> NSTextView {
    // TextKit 1, so the height for a width comes straight from the layout manager.
    let view = NSTextView(usingTextLayoutManager: false)
    view.isEditable = false
    view.isSelectable = true
    view.isRichText = false
    view.drawsBackground = false
    view.textContainerInset = .zero
    view.isVerticallyResizable = false
    view.isHorizontallyResizable = false
    view.textContainer?.lineFragmentPadding = 0
    view.textContainer?.widthTracksTextView = true
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return view
  }

  func updateNSView(_ view: NSTextView, context: Context) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = lineSpacing
    let attributed = NSAttributedString(
      string: text,
      attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    if view.textStorage?.isEqual(to: attributed) != true {
      view.textStorage?.setAttributedString(attributed)
    }
    if let container = view.textContainer {
      container.maximumNumberOfLines = maximumLines
      container.lineBreakMode = maximumLines > 0 ? .byTruncatingTail : .byWordWrapping
    }
    view.setAccessibilityLabel(accessibilityLabel)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context)
    -> CGSize?
  {
    guard let width = proposal.width, width.isFinite, width > 0,
      let container = view.textContainer, let layout = view.layoutManager
    else { return nil }
    container.size = CGSize(width: width, height: .greatestFiniteMagnitude)
    layout.ensureLayout(for: container)
    let height = layout.usedRect(for: container).height
    return CGSize(width: width, height: height.rounded(.up))
  }
}
