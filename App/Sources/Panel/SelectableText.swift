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
  /// Shown instead of `text` when set; it carries its own font, colors and spacing.
  var attributed: NSAttributedString?
  let font: NSFont
  var color: NSColor = .labelColor
  var lineSpacing: CGFloat = 0
  /// 0 shows every line; otherwise the text is cut off with an ellipsis after this many.
  var maximumLines = 0
  var accessibilityLabel: String?
  /// A click on text that carries `.dictChange`, with its value, instead of selecting.
  var onClickChange: ((Int) -> Void)?

  func makeNSView(context: Context) -> ChangeTextView {
    // TextKit 1, so the height for a width comes straight from the layout manager.
    let view = ChangeTextView(usingTextLayoutManager: false)
    // Draws the proofread diff's tints and the current change's underline.
    view.textContainer?.replaceLayoutManager(DiffLayoutManager())
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

  func updateNSView(_ view: ChangeTextView, context: Context) {
    view.onClickChange = onClickChange
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = lineSpacing
    let attributed =
      self.attributed
      ?? NSAttributedString(
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

  func sizeThatFits(_ proposal: ProposedViewSize, nsView view: ChangeTextView, context: Context)
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

/// A text view where a click on a change of a correction toggles it rather than starting a
/// selection (architecture 11.5).
final class ChangeTextView: NSTextView {
  var onClickChange: ((Int) -> Void)?

  override func mouseDown(with event: NSEvent) {
    if let onClickChange, let change = change(at: convert(event.locationInWindow, from: nil)) {
      onClickChange(change)
    } else {
      super.mouseDown(with: event)
    }
  }

  /// The change under `point`, in the view's coordinates; nil beside the text, where the
  /// layout manager would answer with the nearest character.
  func change(at point: CGPoint) -> Int? {
    guard let layout = layoutManager, let container = textContainer, let storage = textStorage,
      storage.length > 0
    else { return nil }
    let origin = textContainerOrigin
    let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    let glyph = layout.glyphIndex(for: local, in: container)
    let bounds = layout.boundingRect(
      forGlyphRange: NSRange(location: glyph, length: 1), in: container)
    guard bounds.contains(local) else { return nil }
    let index = layout.characterIndexForGlyph(at: glyph)
    guard index < storage.length else { return nil }
    return storage.attribute(.dictChange, at: index, effectiveRange: nil) as? Int
  }
}
