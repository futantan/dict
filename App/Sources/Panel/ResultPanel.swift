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
  /// Called for Return while the panel shows a correction that can replace the selection.
  var onConfirm: () -> Void = {}
  var canReplace: () -> Bool = { false }
  /// Whether the panel shows a word card, whose actions answer ⌘S and ⌘P.
  var showsCard: () -> Bool = { false }
  /// Called for a key that stands for a panel action.
  var onPerform: (PanelAction.ID) -> Void = { _ in }

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
    // `.ignoresCycle`: ⌘` cycles through Dict's own windows, never to the panel.
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
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
      hasResult: copyableText() != nil, canReplace: canReplace(), showsCard: showsCard())
  }

  override func sendEvent(_ event: NSEvent) {
    guard event.type == .keyDown else { return super.sendEvent(event) }
    switch route(for: event) {
    case .dismiss:
      onEscape()
    case .confirm:
      onConfirm()
    case .perform(let action):
      onPerform(action)
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
  /// macOS 26, the popover material before. A nearly opaque `PanelBacking` lies between the
  /// material and the content, so the text stays readable over any window behind the panel.
  private static func background(around content: NSView) -> NSView {
    let backed = PanelBacking(content: content)
    if #available(macOS 26, *) {
      let glass = NSGlassEffectView()
      glass.cornerRadius = cornerRadius
      glass.contentView = backed
      // Without this mask the window shadow follows the rectangular frame and draws a
      // grey outline around the rounded glass (seen on macOS 26).
      glass.wantsLayer = true
      glass.layer?.cornerRadius = cornerRadius
      glass.layer?.cornerCurve = .continuous
      glass.layer?.masksToBounds = true
      return glass
    }
    let effect = NSVisualEffectView()
    effect.material = .popover
    effect.blendingMode = .behindWindow
    effect.state = .active
    effect.maskImage = roundedMask(radius: cornerRadius)
    backed.frame = effect.bounds
    backed.autoresizingMask = [.width, .height]
    effect.addSubview(backed)
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

/// The panel's fill over the material: the window background, nearly opaque. On the bare
/// material a dark window behind a light panel shows through and darkens it while the text
/// keeps the light appearance's colours, so the secondary text all but disappears.
final class PanelBacking: NSView {
  /// Enough to hide the text of a window behind; the rest leaves a trace of the material.
  static let opacity: CGFloat = 0.95

  static var color: NSColor { .windowBackgroundColor.withAlphaComponent(opacity) }

  init(content: NSView) {
    super.init(frame: content.frame)
    // The material's own mask does not reach its subviews; the same corners as the glass.
    wantsLayer = true
    layer?.cornerRadius = ResultPanel.cornerRadius
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    content.frame = bounds
    content.autoresizingMask = [.width, .height]
    addSubview(content)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func draw(_ dirtyRect: CGRect) {
    // The dynamic colour resolves in the view's appearance while it draws.
    Self.color.setFill()
    bounds.fill(using: .copy)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}
