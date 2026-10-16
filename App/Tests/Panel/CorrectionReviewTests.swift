// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import SwiftUI
import Testing

@testable import DictApp

private let applied = AppliedEdits(
  text: "the cat sat on a mat",
  segments: [
    .changed(from: "teh", to: "the"), .unchanged(" cat sat on "), .changed(from: "", to: "a "),
    .unchanged("mat"),
  ])

/// Accepting and declining a correction's changes one by one (architecture 11.5).
struct CorrectionReviewTests {
  @Test func everyChangeStartsAcceptedWithNoneCurrent() {
    let correction = Correction(applied, replaceable: true)
    #expect(correction.accepted == [0, 1])
    #expect(correction.current == nil)
    #expect(correction.text == "the cat sat on a mat")
    #expect(correction.canReplace)
  }

  @Test func togglingDeclinesThenAcceptsAndMakesTheChangeCurrent() {
    var correction = Correction(applied, replaceable: true)
    correction.toggle(1)
    #expect(correction.accepted == [0])
    #expect(correction.current == 1)
    #expect(correction.text == "the cat sat on mat")
    correction.toggle(1)
    #expect(correction.accepted == [0, 1])
    correction.toggle(5)
    #expect(correction.accepted == [0, 1])
  }

  @Test func declinedReturnLastsUntilTheNextStep() {
    var correction = Correction(applied, replaceable: true)
    correction.declinedReturn = true
    correction.moveCurrent(by: 1)
    #expect(!correction.declinedReturn)
    correction.declinedReturn = true
    correction.toggleCurrent()
    #expect(!correction.declinedReturn)
  }

  @Test func movingStopsAtTheFirstAndTheLastChange() {
    var correction = Correction(applied, replaceable: true)
    correction.moveCurrent(by: 1)
    #expect(correction.current == 0)
    correction.moveCurrent(by: -1)
    #expect(correction.current == 0)
    correction.moveCurrent(by: 1)
    correction.moveCurrent(by: 1)
    #expect(correction.current == 1)
    correction.toggleCurrent()
    #expect(correction.accepted == [0])
  }

  /// The first ← marks the last change; the first Space only marks the first change.
  @Test func theFirstStepOnlyMarksAChange() {
    var backwards = Correction(applied, replaceable: true)
    backwards.moveCurrent(by: -1)
    #expect(backwards.current == 1)
    var space = Correction(applied, replaceable: true)
    space.toggleCurrent()
    #expect(space.current == 0)
    #expect(space.accepted == [0, 1])
  }

  /// A correction appears with no change underlined.
  @MainActor @Test func aNewCorrectionShowsNoMark() {
    let correction = Correction(applied, replaceable: true)
    let text = diffText(
      correction.proposed.segments, accepted: correction.accepted, current: correction.current)
    var underlined = false
    text.enumerateAttribute(.underlineStyle, in: NSRange(location: 0, length: text.length)) {
      value, _, _ in if value != nil { underlined = true }
    }
    #expect(!underlined)
  }

  @Test func withoutChangesThereIsNothingToReview() {
    var correction = Correction(
      AppliedEdits(text: "ok", segments: [.unchanged("ok")]), replaceable: true)
    #expect(correction.current == nil)
    correction.moveCurrent(by: 1)
    correction.toggleCurrent()
    #expect(correction.current == nil)
    #expect(correction.accepted.isEmpty)
    #expect(!correction.canReplace)
  }

  /// The vocabulary log gets the changes that were made, not the declined ones.
  @Test func theLogGetsTheAcceptedChangesOnly() {
    var correction = Correction(applied, replaceable: true)
    correction.toggle(1)
    #expect(correction.editsJSON == #"[{"right":"the","wrong":"teh"}]"#)
  }

  @Test func theFooterCountsTheAcceptedChanges() {
    #expect(WritingStrings.changes(3, of: 3) == WritingStrings.changes(3))
    #expect(WritingStrings.changes(1, of: 3) == "1 of 3 changes")
  }
}

@MainActor
struct DiffTextReviewTests {
  /// A declined change shows the original plainly and its suggestion faint and struck
  /// through; every character of a change carries its index.
  @Test func aDeclinedChangeShowsTheOriginal() throws {
    let text = diffText(applied.segments, accepted: [1], current: 1)
    #expect(text.string == "teh the cat sat on a mat")
    let original = text.attributes(at: 0, effectiveRange: nil)
    #expect(original[.foregroundColor] as? NSColor == Palette.textPrimary)
    #expect(original[.strikethroughStyle] == nil)
    #expect(original[.dictChange] as? Int == 0)
    let suggestion = text.attributes(at: 4, effectiveRange: nil)
    #expect(suggestion[.foregroundColor] as? NSColor == Palette.textTertiary)
    #expect(suggestion[.strikethroughStyle] != nil)
    #expect(suggestion[.backgroundColor] == nil)
    #expect(text.attributes(at: 9, effectiveRange: nil)[.dictChange] == nil)
  }

  @Test func theCurrentChangeIsUnderlinedInTheAccentColour() {
    let text = diffText(applied.segments, accepted: [0, 1], current: 1)
    let inserted = (text.string as NSString).range(of: "a ")
    let current = text.attributes(at: inserted.location, effectiveRange: nil)
    #expect(current[.underlineColor] as? NSColor == Palette.accent)
    #expect(current[.dictChange] as? Int == 1)
    #expect(text.attributes(at: 0, effectiveRange: nil)[.underlineStyle] == nil)
  }

  /// A click on a change hits it; a click beside the text hits nothing, although the layout
  /// manager would answer with the nearest character.
  @Test func clicksHitTheChangeUnderThePointer() throws {
    let view = ChangeTextView(usingTextLayoutManager: false)
    view.frame = CGRect(x: 0, y: 0, width: 300, height: 40)
    view.textContainerInset = .zero
    view.textStorage?.setAttributedString(diffText(applied.segments))
    let layout = try #require(view.layoutManager)
    let container = try #require(view.textContainer)
    layout.ensureLayout(for: container)

    func center(of characters: NSRange) -> CGPoint {
      let glyphs = layout.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
      let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
      return CGPoint(x: rect.midX, y: rect.midY)
    }
    let string = view.string as NSString
    #expect(view.change(at: center(of: string.range(of: "teh"))) == 0)
    #expect(view.change(at: center(of: string.range(of: "a "))) == 1)
    #expect(view.change(at: center(of: string.range(of: "cat"))) == nil)
    #expect(view.change(at: CGPoint(x: 295, y: 5)) == nil)
  }
}

/// The panel turns ←, → and Space into review steps while it shows changes and nothing has
/// focus, and Tab still enters the key view loop.
@MainActor
struct PanelReviewKeyTests {
  private func makePanel() throws -> ResultPanel {
    let state = try #require(PanelGallery.writeStates.first { $0.name == "proofread-partial" })
      .state
    let hosting = NSHostingView(rootView: PanelView(model: PanelModel(state: state)))
    hosting.sizingOptions = []
    let panel = ResultPanel(content: hosting)
    panel.setFrame(CGRect(x: 0, y: 0, width: PanelLayout.width, height: 300), display: false)
    panel.contentView?.layoutSubtreeIfNeeded()
    #expect(panel.makeFirstResponder(nil))
    return panel
  }

  private func key(_ panel: NSWindow, _ code: UInt16, _ characters: String) throws -> NSEvent {
    try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: panel.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
  }

  @Test func arrowsAndSpaceReviewTheChanges() throws {
    let panel = try makePanel()
    var steps: [String] = []
    panel.showsChanges = { true }
    panel.onMoveChange = { steps.append("move \($0)") }
    panel.onToggleChange = { steps.append("toggle") }
    panel.sendEvent(try key(panel, PanelKeys.rightArrow, "\u{F703}"))
    panel.sendEvent(try key(panel, PanelKeys.leftArrow, "\u{F702}"))
    panel.sendEvent(try key(panel, PanelKeys.space, " "))
    #expect(steps == ["move 1", "move -1", "toggle"])
  }

  @Test func tabStillEntersTheKeyViewLoop() throws {
    let panel = try makePanel()
    panel.showsChanges = { true }
    panel.sendEvent(try key(panel, PanelKeys.tab, "\t"))
    #expect(panel.firstResponder is NSView)
  }
}
