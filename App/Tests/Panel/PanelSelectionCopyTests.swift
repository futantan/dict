// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import Testing

@testable import DictApp

/// ⌘C copies the part of the result the user selected, not the whole result (architecture
/// 11.5). Only the routing is checked, so the test never touches the clipboard.
@MainActor
struct PanelSelectionCopyTests {
  private let result = "你好，世界。今天天气很好。"

  private func makePanel() -> (ResultPanel, NSTextView?) {
    let model = PanelModel(state: PanelState(source: "Hello, world.", phase: .result(result)))
    let hosting = NSHostingView(rootView: PanelView(model: model))
    hosting.sizingOptions = []
    let panel = ResultPanel(content: hosting)
    panel.setFrame(CGRect(x: 0, y: 0, width: PanelLayout.width, height: 300), display: false)
    panel.copyableText = { [result] in result }
    panel.contentView?.layoutSubtreeIfNeeded()
    return (panel, Self.textViews(in: panel.contentView).first { $0.string == result })
  }

  private static func textViews(in view: NSView?) -> [NSTextView] {
    guard let view else { return [] }
    return (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
  }

  private func commandC(_ panel: NSWindow) throws -> NSEvent {
    try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
        windowNumber: panel.windowNumber, context: nil, characters: "c",
        charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
  }

  @Test func theResultIsASelectableTextView() throws {
    let (_, textView) = makePanel()
    let view = try #require(textView)
    #expect(view.isSelectable)
    #expect(!view.isEditable)
    #expect(view.acceptsFirstResponder)
  }

  @Test func commandCCopiesTheSelectedPart() throws {
    let (panel, textView) = makePanel()
    let view = try #require(textView)
    #expect(panel.makeFirstResponder(view))
    view.setSelectedRange(NSRange(location: 0, length: 2))

    #expect(panel.route(for: try commandC(panel)) == .edit(#selector(NSText.copy(_:))))
  }

  @Test func commandCWithoutASelectionCopiesTheResult() throws {
    let (panel, textView) = makePanel()
    let view = try #require(textView)
    #expect(panel.makeFirstResponder(view))
    view.setSelectedRange(NSRange(location: 0, length: 0))

    #expect(panel.route(for: try commandC(panel)) == .copyResult)
  }
}
