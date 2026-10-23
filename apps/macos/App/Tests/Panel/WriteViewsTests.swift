// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import Testing

@testable import DictApp

private let applied = AppliedEdits(
  text: "the cat sat on a mat",
  segments: [
    .changed(from: "teh", to: "the"), .unchanged(" cat sat on "), .changed(from: "", to: "a "),
    .unchanged("mat"),
  ])

/// What the Write flow's bar says and offers (Design/option-a, 校对 and 外译).
@MainActor
struct WriteBarTests {
  @Test func theSummaryFollowsTheReview() {
    var correction = Correction(applied, replaceable: true)
    #expect(correction.summary == StatusPill(WritingStrings.changes(2, of: 2), tone: .accent))
    correction.toggle(0)
    correction.toggle(1)
    #expect(correction.summary.text == WritingStrings.allDeclined)
    #expect(correction.summary.tone == .neutral)
    correction.declinedReturn = true
    #expect(correction.summary.text == WritingStrings.nothingReplaced)
    #expect(correction.summary.tone == .warning)
    #expect(correction.summary.symbol != nil)
  }

  @Test func aCleanTextAndAReadOnlyFieldSaySo() {
    let clean = Correction(
      AppliedEdits(text: "ok", segments: [.unchanged("ok")]), replaceable: true)
    #expect(clean.summary.text == WritingStrings.noMistakes)
    #expect(clean.summary.tone == .success)
    let readOnly = Correction(applied, replaceable: false)
    #expect(readOnly.summary.text == WritingStrings.cannotReplace)
    #expect(readOnly.summary.tone == .neutral)
    #expect(readOnly.summary.symbol == "lock")
  }

  /// The help shows until the first review step, and not after Return did nothing.
  @Test func theReviewHintShowsUntilTheFirstStep() {
    var correction = Correction(applied, replaceable: true)
    #expect(correction.showsReviewHint)
    correction.moveCurrent(by: 1)
    #expect(!correction.showsReviewHint)
    #expect(
      !Correction(
        AppliedEdits(text: "ok", segments: [.unchanged("ok")]), replaceable: true
      ).showsReviewHint)
  }

  /// Return replaces a translation without issues; one with issues takes ⌘Return, on a
  /// button that does not look like the Return one.
  @Test func theTranslateOutButtonFollowsTheIssues() {
    var translation = TranslateOut(
      text: "We meet at three.", isComplete: true, replaceable: true)
    #expect(translation.replaceButton == .replace)
    translation.issues = [.lengthRatio]
    #expect(translation.replaceButton == .replaceAnyway)
    #expect(translation.summary.tone == .warning)
    translation.replaceable = false
    #expect(translation.replaceButton == nil)
    #expect(TranslateOut(text: "We", replaceable: true).replaceButton == nil)
  }

  @Test func theTranslateOutSummary() {
    let streaming = TranslateOut(text: "We", replaceable: true)
    #expect(streaming.summary == StatusPill(WritingStrings.translateOutTitle, tone: .accent))
    let readOnly = TranslateOut(text: "We meet.", isComplete: true)
    #expect(readOnly.summary.text == WritingStrings.cannotReplace)
    #expect(readOnly.summary.symbol == "lock")
  }

  /// The mockups set the proofread text a size above the body.
  @Test func theProofreadTextIsSixteenPoints() {
    #expect(Typography.proofread.size == 16)
  }
}

@MainActor
struct DiffTintTests {
  /// The insertion's tint hugs its letters: a space at its end is left out, so the box
  /// does not run into the next word.
  @Test func theTintLeavesOutTrailingSpace() {
    let text = diffText(applied.segments)
    let inserted = (text.string as NSString).range(of: "a ")
    #expect(text.attribute(.dictTint, at: inserted.location, effectiveRange: nil) != nil)
    #expect(text.attribute(.dictTint, at: inserted.location + 1, effectiveRange: nil) == nil)
  }

  /// A declined change underlines the words it keeps, not the space after them, unless it
  /// is current and so underlined in the accent colour.
  @Test func aDeclinedOriginalIsUnderlinedThinly() {
    let deletion: [DiffSegment] = [
      .unchanged("lived "), .changed(from: "right ", to: ""), .unchanged("here"),
    ]
    let text = diffText(deletion, accepted: [])
    #expect(
      text.attribute(.underlineColor, at: 6, effectiveRange: nil) as? NSColor
        == Palette.textTertiary)
    #expect(text.attribute(.underlineStyle, at: 11, effectiveRange: nil) == nil)
    let replacement = diffText(applied.segments, accepted: [1])
    #expect(replacement.attribute(.underlineStyle, at: 0, effectiveRange: nil) != nil)
    let current = diffText(applied.segments, accepted: [1], current: 0)
    #expect(current.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
    #expect(
      current.attribute(.dictUnderline, at: 0, effectiveRange: nil) as? NSColor
        == Palette.accent)
  }

  /// A declined suggestion has no tint; it is faint and struck through instead.
  @Test func aDeclinedInsertionHasNoTint() {
    let text = diffText(applied.segments, accepted: [0])
    let inserted = (text.string as NSString).range(of: "a ")
    #expect(text.attribute(.dictTint, at: inserted.location, effectiveRange: nil) == nil)
  }
}
