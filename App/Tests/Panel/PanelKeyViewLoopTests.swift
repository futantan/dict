// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import Testing

@testable import DictApp

/// The panel appears with no view focused, so a word card draws no focus ring, yet Tab and
/// ⇧Tab still move focus into the card's actions.
@MainActor
struct PanelKeyViewLoopTests {
  private func makePanel() throws -> ResultPanel {
    let state = try #require(PanelGallery.cardStates.first { $0.name == "card-complete" }).state
    let hosting = NSHostingView(rootView: PanelView(model: PanelModel(state: state)))
    hosting.sizingOptions = []
    let panel = ResultPanel(content: hosting)
    panel.setFrame(CGRect(x: 0, y: 0, width: PanelLayout.width, height: 300), display: false)
    panel.contentView?.layoutSubtreeIfNeeded()
    #expect(panel.makeFirstResponder(nil))
    return panel
  }

  private func tab(_ panel: NSWindow, shift: Bool) throws -> NSEvent {
    try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: shift ? .shift : [], timestamp: 0,
        windowNumber: panel.windowNumber, context: nil, characters: "\t",
        charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: PanelKeys.tab))
  }

  @Test(arguments: [false, true])
  func tabFocusesAViewWhenNothingHasFocus(shift: Bool) throws {
    let panel = try makePanel()
    #expect(panel.firstResponder === panel)
    panel.sendEvent(try tab(panel, shift: shift))
    #expect(panel.firstResponder is NSView)
  }
}
