// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Testing

@testable import DictApp

/// What Return, ⌘Return and ⌘C do with a translate-out (architecture 11.5).
struct TranslateOutStateTests {
  private let done = TranslateOut(
    text: "We meet at three.", isComplete: true, backTranslation: .text("我们三点见。"),
    replaceable: true)

  @Test func whileStreamingNothingReplacesButTheTextCopies() {
    let streaming = PanelPhase.translatedOut(
      TranslateOut(text: "We meet", replaceable: true))
    #expect(!streaming.canReplace)
    #expect(!streaming.canReplaceAnyway)
    #expect(streaming.copyableText == "We meet")
    #expect(PanelPhase.translatedOut(TranslateOut()).copyableText == nil)
  }

  @Test func aCompleteTranslationReplacesOnReturn() {
    #expect(PanelPhase.translatedOut(done).canReplace)
    #expect(PanelPhase.translatedOut(done).canReplaceAnyway)
    #expect(PanelPhase.translatedOut(done).copyableText == "We meet at three.")
  }

  /// The back-translation only helps checking; without it the translation still replaces.
  @Test func aPendingOrFailedBackTranslationDoesNotBlock() {
    for back in [TranslateOut.BackTranslation.pending, .unavailable] {
      var translation = done
      translation.backTranslation = back
      #expect(PanelPhase.translatedOut(translation).canReplace)
    }
  }

  @Test func issuesNeedCommandReturn() {
    var translation = done
    translation.issues = [.lengthRatio]
    #expect(!PanelPhase.translatedOut(translation).canReplace)
    #expect(PanelPhase.translatedOut(translation).canReplaceAnyway)
  }

  @Test func withoutAFieldToWriteItCanOnlyBeCopied() {
    var translation = done
    translation.replaceable = false
    #expect(!PanelPhase.translatedOut(translation).canReplace)
    #expect(!PanelPhase.translatedOut(translation).canReplaceAnyway)
    #expect(PanelPhase.translatedOut(translation).copyableText == "We meet at three.")
  }

  @Test func aBlankTranslationNeverReplaces() {
    var translation = done
    translation.text = "  \n"
    #expect(!PanelPhase.translatedOut(translation).canReplaceAnyway)
  }

  /// `unchanged` comes with `languageMismatch`; the panel says it once.
  @Test func anUnchangedTranslationIsNamedOnce() {
    var translation = done
    translation.issues = [.languageMismatch, .unchanged]
    #expect(translation.shownIssues == [.unchanged])
    translation.issues = [.languageMismatch, .lostURL]
    #expect(translation.shownIssues == [.languageMismatch, .lostURL])
  }

  /// A correction keeps its rules: Return replaces, ⌘Return is not a second way.
  @Test func aCorrectionIsUnchanged() {
    let applied = AppliedEdits(
      text: "the cat", segments: [.changed(from: "teh", to: "the"), .unchanged(" cat")])
    let phase = PanelPhase.corrected(Correction(applied, replaceable: true))
    #expect(phase.canReplace)
    #expect(!phase.canReplaceAnyway)
  }
}
