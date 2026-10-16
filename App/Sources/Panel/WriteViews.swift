// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import SwiftUI

// The bodies of the Write flow: the proofread diff and the translate-out. Their bars are in
// `ActionBar`.

/// A translate-out: the translation as the main text, then one line with the
/// back-translation, then what to check before replacing (architecture 11.6). The
/// back-translation line is there from the start, so the panel does not grow when it arrives.
struct TranslatedOutView: View {
  let translation: TranslateOut

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.row) {
      if translation.text.isEmpty && !translation.isComplete {
        ProgressLine(text: PanelStrings.translating, height: Typography.result.lineHeight)
      } else {
        ResultText(text: translation.text, isStreaming: !translation.isComplete)
      }
      // A translation left as the original has nothing to translate back.
      if !(translation.isComplete && translation.issues.contains(.unchanged)) {
        BackTranslationLine(translation: translation)
      }
      if translation.isComplete && !translation.shownIssues.isEmpty {
        IssueList(issues: translation.shownIssues)
      }
    }
  }
}

/// The badge, then the back-translation or what stands in for it.
struct BackTranslationLine: View {
  let translation: TranslateOut

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Spacing.buttons) {
      Pill(WritingStrings.backTranslation, tone: .neutral, size: .small)
      content
        .font(Typography.secondary.font)
        .lineSpacing(Typography.secondary.lineSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private var content: some View {
    switch translation.backTranslation {
    case .text(let text):
      Text(text)
        .foregroundStyle(Color(Palette.textSecondary))
        .textSelection(.enabled)
    case .pending where translation.isComplete:
      Text(WritingStrings.backTranslating).foregroundStyle(Color(Palette.textTertiary))
    case .pending:
      Text(WritingStrings.backTranslationWaiting).foregroundStyle(Color(Palette.textTertiary))
    case .unavailable:
      Text(WritingStrings.backTranslationUnavailable)
        .foregroundStyle(Color(Palette.textTertiary))
    }
  }
}

/// The validation's issues, in the warning colours.
struct IssueList: View {
  let issues: [RewriteIssue]

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: "exclamationmark.triangle")
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        ForEach(issues, id: \.self) { issue in
          Text(WritingStrings.issue(issue))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
    }
    .font(Typography.secondary.font)
    .foregroundStyle(Tone.warning.onTint)
  }
}

/// The proofread text with each change in place. An accepted change shows the removed
/// words struck through in red and the inserted ones in green; a declined one shows the
/// original words, then the declined suggestion struck through and faint (a declined
/// deletion, which has none, underlines the kept words thinly). A plain space keeps the two
/// sides from running together. The current change, the one ← → and Space act on, is
/// underlined in the accent colour. Every character of a change carries its index
/// (`.dictChange`) for clicks, and the pointing hand.
///
/// - Parameter accepted: The accepted changes; nil accepts every one.
@MainActor
func diffText(
  _ segments: [DiffSegment], accepted: Set<Int>? = nil, current: Int? = nil
) -> NSAttributedString {
  let red = DiffColor.removed
  let green = DiffColor.inserted
  let paragraph = NSMutableParagraphStyle()
  paragraph.lineSpacing = Typography.body.lineSpacing
  let base: [NSAttributedString.Key: Any] = [
    .font: Typography.body.nsFont, .foregroundColor: Palette.textPrimary,
    .paragraphStyle: paragraph,
  ]
  let text = NSMutableAttributedString()
  var change = 0
  for segment in segments {
    guard case .changed(let from, let to) = segment else {
      if case .unchanged(let run) = segment {
        text.append(NSAttributedString(string: run, attributes: base))
      }
      continue
    }
    let isAccepted = accepted?.contains(change) ?? true
    let isCurrent = change == current
    var marked = base
    marked[.dictChange] = change
    marked[.cursor] = NSCursor.pointingHand
    if isCurrent {
      marked[.underlineStyle] = NSUnderlineStyle.thick.rawValue
      marked[.underlineColor] = Palette.accent
    }
    if !from.isEmpty {
      var removed = marked
      if isAccepted {
        removed[.foregroundColor] = red
        removed[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        removed[.strikethroughColor] = red
      } else if to.isEmpty && !isCurrent {
        // A declined deletion has no faint suggestion to mark it.
        removed[.underlineStyle] = NSUnderlineStyle.single.rawValue
        removed[.underlineColor] = Palette.textSecondary
      }
      text.append(NSAttributedString(string: from, attributes: removed))
    }
    if !from.isEmpty && !to.isEmpty {
      // Underlined with the change when current, so the change reads as one piece.
      text.append(NSAttributedString(string: " ", attributes: marked))
    }
    if !to.isEmpty {
      var inserted = marked
      if isAccepted {
        inserted[.foregroundColor] = green
        inserted[.backgroundColor] = DiffColor.insertedTint
      } else {
        inserted[.foregroundColor] = Palette.textTertiary
        inserted[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        inserted[.strikethroughColor] = Palette.textTertiary
      }
      text.append(NSAttributedString(string: to, attributes: inserted))
    }
    change += 1
  }
  return text
}

extension NSAttributedString.Key {
  /// The index of the change a character of the diff belongs to (`diffText`).
  static let dictChange = NSAttributedString.Key("DictChange")
}

/// The diff's text colours. The system red and green are bright enough for dark mode, but
/// on the light fill green text reads at about 2:1, so in light mode both are darkened to
/// read at 4.5:1 or more on the fill, the strike-through with them.
enum DiffColor {
  static let removed = legible(.systemRed, darkening: 0.2)
  static let inserted = legible(.systemGreen, darkening: 0.45)
  /// Behind the inserted words.
  static let insertedTint = NSColor.systemGreen.withAlphaComponent(0.14)

  private static func legible(_ color: NSColor, darkening fraction: CGFloat) -> NSColor {
    NSColor(name: nil) { appearance in
      guard appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua else { return color }
      return color.blended(withFraction: fraction, of: .black) ?? color
    }
  }
}
