// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import SwiftUI
import Testing

@testable import DictApp

private let renderDirectory = ProcessInfo.processInfo.environment["DICT_PANEL_RENDER_DIR"]
private let showsDemo = ProcessInfo.processInfo.environment["DICT_PANEL_DEMO"] == "1"

/// Renders every gallery state offscreen and, on request, shows them on screen.
///
/// - `TEST_RUNNER_DICT_PANEL_RENDER_DIR=<dir> xcodebuild test …` writes one PNG per state
///   and appearance into `<dir>`; add `-testLanguage zh-Hans` for the Chinese UI.
/// - `TEST_RUNNER_DICT_PANEL_DEMO=1 xcodebuild test …` shows each state in the real panel
///   for a moment, with Finder in front. It takes key focus, so hold the machine-wide UI
///   lock while it runs.
@MainActor
struct PanelGalleryTests {
  @Test func contentHeightIsKnownAfterOneLayoutPass() {
    for (name, state) in PanelGallery.states() {
      let height = Self.layOut(state, appearance: .aqua).height
      #expect(height >= 48, "\(name)")
      #expect(height < 2000, "\(name)")
    }
  }

  /// `PanelController.show` sizes the window right after changing the state, so the new
  /// height must be reported by the same synchronous layout pass, not a later one.
  @Test func stateChangeReportsNewHeightSynchronously() {
    var height: CGFloat = 0
    let model = PanelModel(state: PanelState(source: "a", phase: .generating("b")))
    let view = NSHostingView(rootView: PanelView(model: model, onContentHeight: { height = $0 }))
    view.sizingOptions = []
    view.frame = CGRect(x: 0, y: 0, width: PanelLayout.width, height: 300)
    view.layoutSubtreeIfNeeded()
    let short = height

    model.state = PanelState(
      source: "a", phase: .generating(String(repeating: "word ", count: 200)))
    view.layoutSubtreeIfNeeded()
    #expect(height > short + 100)

    model.state = .input
    view.layoutSubtreeIfNeeded()
    #expect(height == 48)
  }

  /// The first words of a result take the place of the progress line without moving the
  /// panel's bottom edge, in Latin and in Chinese.
  @Test func theFirstWordsKeepThePanelHeight() {
    let source = "他把一句很长的话翻来覆去地想了好几遍。"
    for words in ["He turned", "他把一句"] {
      let waiting = Self.layOut(
        PanelState(source: source, phase: .generating("")), appearance: .aqua)
      let streaming = Self.layOut(
        PanelState(source: source, phase: .generating(words)), appearance: .aqua)
      #expect(waiting.height == streaming.height, "\(words)")
    }
  }

  /// A legacy scroller's width comes out of the trailing margin, so a scrolling panel's
  /// content keeps the width and the right edge of one that does not scroll.
  @Test func aScrollerKeepsTheContentWidth() {
    #expect(PanelLayout.trailingPadding(isScrollable: false, scrollerStyle: .legacy) == 22)
    #expect(PanelLayout.trailingPadding(isScrollable: true, scrollerStyle: .overlay) == 22)
    let legacy = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    #expect(PanelLayout.trailingPadding(isScrollable: true, scrollerStyle: .legacy) == 22 - legacy)
  }

  /// Content taller than the panel scrolls above the bottom bar, which stays at the bottom
  /// of the panel; the height the panel reports includes the bar.
  @Test(arguments: ["result-long", "translate-out-back-long", "card-long"])
  func theBarStaysInATallPanel(name: String) throws {
    let state = try #require(PanelGallery.states().first { $0.name == name }).state
    var contentHeight: CGFloat = 0
    let model = PanelModel(state: state)
    let hosting = NSHostingView(
      rootView: PanelView(model: model, onContentHeight: { contentHeight = $0 }))
    hosting.sizingOptions = []
    // In a window, so the scroll view sizes its document.
    let panel = ResultPanel(content: hosting)
    panel.setFrame(CGRect(x: 0, y: 0, width: PanelLayout.width, height: 300), display: false)
    model.isScrollable = true
    panel.contentView?.layoutSubtreeIfNeeded()
    #expect(contentHeight > 350)

    let scrollView = try #require(Self.firstView(NSScrollView.self, in: hosting))
    let scrolling = scrollView.convert(scrollView.bounds, to: nil)
    let bar = PanelLayout.barHeight
    // The bar's fixed height is what it needs.
    let natural = NSHostingView(rootView: ActionBar(state: state)).fittingSize.height
    #expect(natural + Spacing.panelBottom == bar)
    #expect(scrolling.minY == bar)
    #expect(scrolling.maxY == 300)
    let document = try #require(scrollView.documentView).frame.height
    #expect(document + bar == contentHeight)
  }

  /// The streaming spinner sits right after the last word, on its line, and never past the
  /// trailing edge.
  @Test func theSpinnerFollowsTheLastWord() {
    let style = Typography.result
    let width: CGFloat = 356
    let line = style.lineHeight
    let short = ResultText.spinnerOrigin(after: "He turned", style: style, width: width)
    #expect(short.x > Spacing.tight && short.x < width / 2)
    #expect(abs(short.y + Size.spinner / 2 - line / 2) < 1)

    let longer = ResultText.spinnerOrigin(after: "He turned it over", style: style, width: width)
    #expect(longer.x > short.x)
    #expect(longer.y == short.y)

    let wrapped = ResultText.spinnerOrigin(
      after: String(repeating: "word ", count: 20) + "end", style: style, width: width)
    #expect(wrapped.y > line)

    for count in 1...40 {
      let text = String(repeating: "m", count: count * 2)
      let origin = ResultText.spinnerOrigin(after: text, style: style, width: width)
      #expect(origin.x + Size.spinner <= width, "\(count)")
    }
  }

  /// However the streamed text ends on its line, the spinner covers none of it: a last word
  /// with no room after it wraps with the spinner.
  @Test func theSpinnerNeverCoversTheText() {
    let style = Typography.result
    let width: CGFloat = 356
    let texts = (1...60).flatMap { count in
      [
        (1...count).map { "词\($0)" }.joined(separator: " "),
        String(repeating: "m", count: count),
        String(repeating: "词", count: count),
        String(repeating: "word ", count: count / 3) + "end ",
      ]
    }
    for text in texts {
      let origin = ResultText.spinnerOrigin(after: text, style: style, width: width)
      let spinner = CGRect(origin: origin, size: CGSize(width: Size.spinner, height: Size.spinner))
      #expect(spinner.maxX <= width, "\(text)")

      let storage = NSTextStorage(
        attributedString: ResultText.shown(text, isStreaming: true, style: style))
      let layout = NSLayoutManager()
      let container = NSTextContainer(
        size: CGSize(width: width, height: .greatestFiniteMagnitude))
      container.lineFragmentPadding = 0
      layout.addTextContainer(container)
      storage.addLayoutManager(layout)
      layout.ensureLayout(for: container)
      let string = storage.string as NSString
      for glyph in 0..<layout.numberOfGlyphs {
        let character = layout.characterIndexForGlyph(at: glyph)
        guard string.substring(with: NSRange(location: character, length: 1)) != " " else {
          continue
        }
        var box = layout.boundingRect(
          forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        // The last character's box takes in the room left for the spinner.
        if storage.attribute(.kern, at: character, effectiveRange: nil) != nil {
          box.size.width -= ResultText.spinnerRoom
        }
        #expect(!box.intersects(spinner), "\(text)")
      }
    }
  }

  /// The back-translation line is there before the back-translation arrives, so a one-line
  /// back-translation, or none, leaves the panel's height as it was; in Latin and Chinese.
  @Test func theBackTranslationKeepsThePanelHeight() {
    let text = "I've already reviewed this PR."
    func height(_ back: TranslateOut.BackTranslation) -> CGFloat {
      Self.layOut(
        PanelState(
          source: "这个 PR 我已经 review 过了",
          phase: .translatedOut(
            TranslateOut(text: text, isComplete: true, backTranslation: back, replaceable: true))),
        appearance: .aqua
      ).height
    }
    let waiting = height(.pending)
    #expect(height(.text("这个 PR 我已经看过了。")) == waiting)
    #expect(height(.text("I have already looked at it.")) == waiting)
    #expect(height(.unavailable) == waiting)
    // Nor does the translation's completion move it.
    let streaming = Self.layOut(
      PanelState(
        source: "这个 PR 我已经 review 过了",
        phase: .translatedOut(TranslateOut(text: text, replaceable: true))),
      appearance: .aqua
    ).height
    #expect(streaming == waiting)
  }

  /// The content lies on a nearly opaque fill, not on the bare material, so a window behind
  /// the panel neither shows through nor darkens its text.
  @Test func theContentLiesOnANearlyOpaqueFill() throws {
    let panel = PanelController().window
    let backing = try #require(Self.firstView(PanelBacking.self, in: panel.contentView))
    #expect(PanelBacking.opacity >= 0.9)
    #expect(PanelBacking.color.alphaComponent == PanelBacking.opacity)
    let hosting = try #require(backing.subviews.first as? NSHostingView<PanelView>)

    // It fills the panel at any size, the content with it.
    panel.setContentSize(CGSize(width: PanelLayout.width, height: 300))
    panel.contentView?.layoutSubtreeIfNeeded()
    #expect(backing.frame.size == panel.contentView?.bounds.size)
    #expect(hosting.frame == backing.bounds)
  }

  /// The panel follows the app's appearance, not the windows behind it: from macOS 26 the
  /// glass adapts its content's colour scheme to the backdrop, which offscreen it never
  /// does, so the test stands in for it by giving every view above the fill the opposite
  /// appearance.
  @Test func theFillFollowsTheAppAppearanceNotTheBackdrop() throws {
    let panel = PanelController().window
    let backing = try #require(Self.firstView(PanelBacking.self, in: panel.contentView))
    let hosting = try #require(backing.subviews.first)
    defer { NSApp.appearance = nil }

    for (app, backdrop) in [
      (NSAppearance.Name.aqua, NSAppearance.Name.darkAqua), (.darkAqua, .aqua),
    ] {
      NSApp.appearance = NSAppearance(named: app)
      var view = backing.superview
      while let above = view {
        above.appearance = NSAppearance(named: backdrop)
        view = above.superview
      }
      #expect(backing.effectiveAppearance.name == app)
      #expect(hosting.effectiveAppearance.name == app)
    }
  }

  private static func firstView<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
    guard let view else { return nil }
    if let match = view as? T { return match }
    for subview in view.subviews {
      if let match = firstView(type, in: subview) { return match }
    }
    if #available(macOS 26, *), let glass = view as? NSGlassEffectView {
      return firstView(type, in: glass.contentView)
    }
    return nil
  }

  /// ⌘` cycles through Dict's own windows and skips the panel.
  @Test func panelIsLeftOutOfWindowCycling() {
    let panel = PanelController().window
    #expect(panel.collectionBehavior.contains(.ignoresCycle))
    #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
  }

  @Test(.enabled(if: renderDirectory != nil))
  func renderGallery() throws {
    let directory = URL(fileURLWithPath: try #require(renderDirectory))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let language = PanelGallery.isChineseUI ? "zh" : "en"
    // The long card and translation scroll only on a small screen.
    let smallScreen = PanelGallery.states()
      .filter { ["card-long", "translate-out-back-long"].contains($0.name) }
      .map { (name: "\($0.name)-small-screen", state: $0.state, maxHeight: CGFloat(300)) }
    let states = PanelGallery.states().map { ($0.name, $0.state, Self.maxHeight) } + smallScreen
    for (name, state, maxHeight) in states {
      for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let png = try #require(Self.render(state, appearance: appearance, maxHeight: maxHeight))
        try png.write(to: directory.appendingPathComponent("\(language)-\(scheme)-\(name).png"))
      }
    }
  }

  @Test(.enabled(if: showsDemo))
  func demoOnScreen() async throws {
    let finder = try #require(
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first)
    finder.activate()
    try await Task.sleep(for: .milliseconds(500))
    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    // While the screen is locked no window can become key.
    try #require(front != "com.apple.loginwindow", "The screen is locked")

    let controller = PanelController()
    var dismissals: [PanelDismissal] = []
    controller.onDismiss = { dismissals.append($0) }
    let visible = try #require(NSScreen.main?.visibleFrame)
    let selection = CGRect(x: visible.midX - 200, y: visible.midY + 100, width: 240, height: 18)

    for (_, state) in PanelGallery.states() {
      controller.show(state, near: .selection(selection))
      try await Task.sleep(for: .milliseconds(1200))
      // A key non-activating panel makes `NSApp.isActive` true, yet the other app stays
      // frontmost and keeps the menu bar, which is what "not activating" means here.
      #expect(controller.window.isKeyWindow)
      #expect(NSWorkspace.shared.frontmostApplication?.bundleIdentifier == front)
      #expect(NSWorkspace.shared.menuBarOwningApplication?.bundleIdentifier == front)
      #expect(controller.window.frame.maxY == selection.minY - PanelLayout.gap)
    }

    // Streaming keeps the top edge in place while the panel grows.
    let source = PanelGallery.states()[4].state.source
    controller.show(PanelState(source: source, phase: .generating("")), near: .selection(selection))
    let top = controller.window.frame.maxY
    var text = ""
    for word in String(repeating: "streaming words grow the panel ", count: 30).split(
      separator: " ")
    {
      text += word + " "
      controller.update(PanelState(source: source, phase: .generating(text)))
      try await Task.sleep(for: .milliseconds(15))
    }
    #expect(controller.window.frame.maxY == top)
    #expect(controller.window.frame.height > 150)

    // Esc hides and reports it; the frontmost app never changed.
    let escape = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: controller.window.windowNumber, context: nil, characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: PanelKeys.escape))
    controller.window.sendEvent(escape)
    #expect(!controller.isVisible)
    #expect(dismissals == [.escape])
    #expect(NSWorkspace.shared.frontmostApplication?.bundleIdentifier == front)
    // Key focus goes back to the frontmost app.
    try await Task.sleep(for: .milliseconds(300))
    #expect(!NSApp.isActive)
    #expect(NSApp.keyWindow == nil)
  }

  // MARK: - Offscreen rendering

  private struct Layout {
    let view: NSView
    let height: CGFloat
  }

  /// The panel's height cap, 60% of the screen, on a laptop screen.
  private static let maxHeight: CGFloat = 483

  /// Lays the panel content out offscreen the way `PanelController` does: one layout pass
  /// reports the content height, then the view takes the capped height.
  private static func layOut(
    _ state: PanelState, appearance: NSAppearance.Name, maxHeight: CGFloat = maxHeight
  ) -> Layout {
    var height: CGFloat = 0
    let model = PanelModel(state: state)
    let view = NSHostingView(rootView: PanelView(model: model, onContentHeight: { height = $0 }))
    view.sizingOptions = []
    view.appearance = NSAppearance(named: appearance)
    view.frame = CGRect(x: 0, y: 0, width: PanelLayout.width, height: 900)
    view.layoutSubtreeIfNeeded()
    let shown = min(height.rounded(.up), maxHeight)
    view.frame.size.height = shown
    model.isScrollable = shown < height
    view.layoutSubtreeIfNeeded()
    return Layout(view: view, height: height)
  }

  /// Draws the content over the panel's fill, with the panel's corner radius and a shadow,
  /// on a neutral backdrop, at 2x.
  private static func render(
    _ state: PanelState, appearance: NSAppearance.Name, maxHeight: CGFloat
  ) -> Data? {
    let content = layOut(state, appearance: appearance, maxHeight: maxHeight).view
    // The panel's corners clip the content, as `PanelBacking` does.
    content.wantsLayer = true
    content.layer?.cornerRadius = ResultPanel.cornerRadius
    content.layer?.cornerCurve = .continuous
    content.layer?.masksToBounds = true
    let inset: CGFloat = 32
    let canvas = Canvas(
      frame: CGRect(
        x: 0, y: 0, width: content.bounds.width + inset * 2,
        height: content.bounds.height + inset * 2))
    canvas.panelRect = canvas.bounds.insetBy(dx: inset, dy: inset)
    let window = NSWindow(
      contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: appearance)
    window.contentView = canvas
    content.frame.origin = canvas.panelRect.origin
    canvas.addSubview(content)
    canvas.layoutSubtreeIfNeeded()

    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas.bounds.width * 2),
        pixelsHigh: Int(canvas.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
        bitsPerPixel: 0)
    else { return nil }
    bitmap.size = canvas.bounds.size
    canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
    return bitmap.representation(using: .png, properties: [:])
  }

  /// A backdrop with a rounded, shadowed panel shape.
  private final class Canvas: NSView {
    var panelRect = CGRect.zero

    override func draw(_ dirtyRect: CGRect) {
      let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      let backdrop = NSColor(white: dark ? 0.12 : 0.82, alpha: 1)
      backdrop.setFill()
      bounds.fill()
      let radius = ResultPanel.cornerRadius
      let shape = NSBezierPath(roundedRect: panelRect, xRadius: radius, yRadius: radius)
      NSGraphicsContext.saveGraphicsState()
      let shadow = NSShadow()
      shadow.shadowBlurRadius = 24
      shadow.shadowOffset = CGSize(width: 0, height: -8)
      shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.6 : 0.25)
      shadow.set()
      backdrop.setFill()
      shape.fill()
      NSGraphicsContext.restoreGraphicsState()
      // The panel's own fill over what lies behind it; the material itself does not render
      // offscreen.
      PanelBacking.color.setFill()
      shape.fill()
    }
  }
}
