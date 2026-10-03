// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The result panel's window (architecture 11.1).
///
/// It becomes key so it receives Return, Esc and input-method events, but it never
/// activates Dict: the app the text came from stays frontmost and only loses its key window
/// while the panel is shown.
final class ResultPanel: NSPanel {
  /// Called for Esc; the controller decides what hiding means.
  var onEscape: () -> Void = {}
  /// The text ⌘C copies when nothing in the panel is selected.
  var copyableText: () -> String? = { nil }

  /// Corner radius of the panel's background.
  static var cornerRadius: CGFloat {
    if #available(macOS 26, *) { 18 } else { 12 }
  }

  init(content: NSView) {
    super.init(
      contentRect: CGRect(x: 0, y: 0, width: PanelLayout.width, height: 48),
      styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered, defer: true)
    isFloatingPanel = true
    level = .floating
    hidesOnDeactivate = false
    becomesKeyOnlyIfNeeded = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    isReleasedWhenClosed = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    animationBehavior = .none
    setAccessibilityIdentifier("dict.panel")
    contentView = Self.background(around: content)
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  /// What a key press does, given the first responder: a selection in the source or result
  /// text, or in the input field, is copied instead of the whole result.
  func route(for event: NSEvent) -> PanelKeyRoute {
    let textView = firstResponder as? NSTextView
    return PanelKeys.route(
      keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
      modifiers: event.modifierFlags, hasMarkedText: textView?.hasMarkedText() ?? false,
      hasSelectedText: (textView?.selectedRange().length ?? 0) > 0,
      hasResult: copyableText() != nil)
  }

  override func sendEvent(_ event: NSEvent) {
    guard event.type == .keyDown else { return super.sendEvent(event) }
    switch route(for: event) {
    case .dismiss:
      onEscape()
    case .copyResult:
      if let text = copyableText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
      }
    case .edit(let action):
      if !NSApp.sendAction(action, to: nil, from: self) { super.sendEvent(event) }
    case .pass:
      super.sendEvent(event)
    }
  }

  /// Wraps the content in the system material with rounded corners: Liquid Glass from
  /// macOS 26, the popover material before.
  private static func background(around content: NSView) -> NSView {
    if #available(macOS 26, *) {
      let glass = NSGlassEffectView()
      glass.cornerRadius = cornerRadius
      glass.contentView = content
      return glass
    }
    let effect = NSVisualEffectView()
    effect.material = .popover
    effect.blendingMode = .behindWindow
    effect.state = .active
    effect.maskImage = roundedMask(radius: cornerRadius)
    content.frame = effect.bounds
    content.autoresizingMask = [.width, .height]
    effect.addSubview(content)
    return effect
  }

  /// A stretchable rounded-rectangle mask; the corners keep their shape at any size.
  private static func roundedMask(radius: CGFloat) -> NSImage {
    let side = radius * 2 + 1
    let image = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
      return true
    }
    image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    image.resizingMode = .stretch
    return image
  }
}
