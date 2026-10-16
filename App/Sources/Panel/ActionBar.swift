// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import SwiftUI

/// The panel's bottom bar for each phase that has one (`BottomBar`): what happened in a pill
/// on the left, the icon buttons, then the primary action.
struct ActionBar: View {
  let state: PanelState
  var onAction: (PanelAction.ID) -> Void = { _ in }
  /// Return, ⌘Return (true) or a click on Replace.
  var onConfirm: (_ anyway: Bool) -> Void = { _ in }

  /// Whether `state` has a bar; a notice's buttons are its own.
  nonisolated static func shows(_ state: PanelState) -> Bool {
    switch state.phase {
    case .generating, .result, .partial, .checking, .corrected, .card, .translatedOut: true
    case .input, .reading, .failure, .needsSetup: false
    }
  }

  var body: some View {
    switch state.phase {
    case .generating(let text):
      translationBar(text: text, isPartial: false, isDone: false)
    case .result(let text):
      translationBar(text: text, isPartial: false, isDone: true)
    case .partial(let text):
      translationBar(text: text, isPartial: true, isDone: true)
    case .checking:
      BottomBar(status: { Pill(WritingStrings.checking, isBusy: true) }, icons: {})
    case .corrected(let correction):
      correctedBar(correction)
    case .translatedOut(let translation):
      translatedOutBar(translation)
    case .card(let card):
      cardBar(card)
    case .input, .reading, .failure, .needsSetup:
      EmptyView()
    }
  }

  // MARK: Translation

  /// A translation copies once it is done; a word or phrase can be looked up instead.
  private func translationBar(text: String, isPartial: Bool, isDone: Bool) -> some View {
    BottomBar(
      status: {
        if isPartial {
          Pill(PanelStrings.incomplete, tone: .warning)
        }
      },
      icons: {
        if state.offersLookUp {
          IconButton(title: CardStrings.lookUp, symbol: "character.book.closed") {
            onAction(CardStrings.lookUpAction)
          }
        }
        IconButton(title: PanelStrings.copy, symbol: "doc.on.doc", shortcut: "⌘C") {
          copyToClipboard(text)
        }
        .disabled(!isDone || text.isEmpty)
      })
  }

  // MARK: Write

  private func correctedBar(_ correction: Correction) -> some View {
    BottomBar(
      status: { correctedStatus(correction) },
      icons: {
        IconButton(title: WritingStrings.copyAction, symbol: "doc.on.doc", shortcut: "⌘C") {
          copyToClipboard(correction.text)
        }
      },
      primary: {
        // With every change declined Return only explains that nothing is replaced.
        if correction.canReplace && !correction.accepted.isEmpty {
          PrimaryButton(title: WritingStrings.replaceAction, keys: "↩") { onConfirm(false) }
        }
      })
  }

  @ViewBuilder private func correctedStatus(_ correction: Correction) -> some View {
    if correction.changeCount == 0 {
      Pill(WritingStrings.noMistakes, symbol: "checkmark", tone: .success)
    } else if correction.declinedReturn {
      Pill(WritingStrings.nothingReplaced, tone: .warning)
    } else if !correction.canReplace {
      Pill(WritingStrings.cannotReplace, tone: .neutral)
    } else if correction.accepted.isEmpty {
      Pill(WritingStrings.allDeclined, tone: .neutral)
    } else {
      Pill(WritingStrings.changes(correction.accepted.count, of: correction.changeCount))
    }
  }

  private func translatedOutBar(_ translation: TranslateOut) -> some View {
    BottomBar(
      status: {
        if translation.isComplete && !translation.issues.isEmpty {
          Pill(WritingStrings.checkBeforeReplacing, tone: .warning)
        } else if translation.isComplete && !translation.replaceable {
          Pill(WritingStrings.cannotReplace, tone: .neutral)
        } else {
          Pill(WritingStrings.translateOutTitle)
        }
      },
      icons: {
        IconButton(title: WritingStrings.copyAction, symbol: "doc.on.doc", shortcut: "⌘C") {
          copyToClipboard(translation.text)
        }
        .disabled(!translation.isComplete || translation.text.isEmpty)
      },
      primary: {
        if translation.replacesOnReturn {
          PrimaryButton(title: WritingStrings.replaceAction, keys: "↩") { onConfirm(false) }
        } else if translation.canReplace {
          SecondaryButton(title: WritingStrings.replaceAnywayAction, keys: "⌘↩") {
            onConfirm(true)
          }
        }
      })
  }

  // MARK: Card

  /// The encounters from the second lookup on; the star is on the card's header.
  private func cardBar(_ card: CardState) -> some View {
    BottomBar(
      status: {
        if let count = card.shownEncounters {
          Pill(CardStrings.encounters(count), symbol: "clock.arrow.circlepath")
        }
      },
      icons: {
        IconButton(title: CardStrings.pronounce, symbol: "speaker.wave.2", shortcut: "⌘P") {
          onAction(CardStrings.pronounceAction)
        }
        IconButton(title: CardStrings.translateAsSentence, symbol: "translate") {
          onAction(CardStrings.translateAction)
        }
      })
  }
}

private func copyToClipboard(_ text: String) {
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(text, forType: .string)
}
