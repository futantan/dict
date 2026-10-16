// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import SwiftUI

// The bodies of the Write flow: the proofread diff and the translate-out, and what their
// bars say (Design/option-a, 校对 and 外译). The bars themselves are in `ActionBar`.

// MARK: Proofread

/// The text being proofread, greyed until the diff takes its place.
struct CheckingView: View {
  let text: String

  var body: some View {
    SelectableText(
      text: text, font: Typography.proofread.nsFont, color: Palette.textSecondary,
      lineSpacing: Typography.proofread.lineSpacing)
  }
}

/// The diff, and how to review it until the first review step.
struct CorrectedView: View {
  let correction: Correction
  let onToggleChange: (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.section) {
      SelectableText(
        text: correction.text,
        attributed: diffText(
          correction.proposed.segments, accepted: correction.accepted,
          current: correction.current),
        font: Typography.proofread.nsFont, lineSpacing: Typography.proofread.lineSpacing,
        accessibilityLabel: WritingStrings.title, onClickChange: onToggleChange
      )
      .help(correction.changeCount > 0 ? WritingStrings.reviewHelp : "")
      if correction.showsReviewHint {
        HStack(spacing: 6) {
          Image(systemName: "keyboard").accessibilityHidden(true)
          Text(WritingStrings.reviewHelp)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(Typography.note.font)
        .foregroundStyle(Color(Palette.textSecondary))
      }
    }
  }
}

/// What a status pill says, in which colours.
struct StatusPill: Equatable {
  let text: String
  var symbol: String?
  var tone: Tone

  init(_ text: String, symbol: String? = nil, tone: Tone) {
    self.text = text
    self.symbol = symbol
    self.tone = tone
  }
}

extension Pill {
  init(_ status: StatusPill) {
    self.init(status.text, symbol: status.symbol, tone: status.tone)
  }
}

extension StatusPill {
  static let cannotReplace = StatusPill(
    WritingStrings.cannotReplace, symbol: "lock", tone: .neutral)
}

extension Correction {
  /// The review keys are explained under the diff until the first of them, or a click.
  var showsReviewHint: Bool { changeCount > 0 && current == nil && !declinedReturn }

  /// The bar's pill: how many changes are accepted, or why Return does not replace.
  var summary: StatusPill {
    if changeCount == 0 {
      StatusPill(WritingStrings.noMistakes, symbol: "checkmark.circle", tone: .success)
    } else if declinedReturn {
      StatusPill(
        WritingStrings.nothingReplaced, symbol: "exclamationmark.triangle", tone: .warning)
    } else if !canReplace {
      .cannotReplace
    } else if accepted.isEmpty {
      StatusPill(WritingStrings.allDeclined, tone: .neutral)
    } else {
      StatusPill(WritingStrings.changes(accepted.count, of: changeCount), tone: .accent)
    }
  }
}

// MARK: Translate out

extension TranslateOut {
  enum ReplaceButton { case replace, replaceAnyway }

  /// Replace ↩ for a translation without issues. One with issues takes ⌘↩, on a secondary
  /// button, so it does not look like what plain Return does.
  var replaceButton: ReplaceButton? {
    if replacesOnReturn { .replace } else if canReplace { .replaceAnyway } else { nil }
  }

  var summary: StatusPill {
    if isComplete && !issues.isEmpty {
      StatusPill(
        WritingStrings.checkBeforeReplacing, symbol: "exclamationmark.triangle", tone: .warning)
    } else if isComplete && !replaceable {
      .cannotReplace
    } else {
      StatusPill(WritingStrings.translateOutTitle, tone: .accent)
    }
  }
}

/// A translate-out: the translation as the main text, then the back-translation in a block,
/// then what to check before replacing (architecture 11.6). The block is there from the
/// start, so the panel does not grow when the back-translation arrives.
struct TranslatedOutView: View {
  let translation: TranslateOut

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.section) {
      if translation.text.isEmpty && !translation.isComplete {
        ProgressLine(text: PanelStrings.translating, height: Typography.result.lineHeight)
      } else {
        ResultText(text: translation.text, isStreaming: !translation.isComplete)
      }
      // A translation left as the original has nothing to translate back.
      if !(translation.isComplete && translation.issues.contains(.unchanged)) {
        BackTranslationBlock(translation: translation)
      }
      if translation.isComplete && !translation.shownIssues.isEmpty {
        IssueList(issues: translation.shownIssues)
      }
    }
  }
}

/// The back-translation, or what stands in for it, under a small heading: grey until it
/// arrives, then in the accent tint.
struct BackTranslationBlock: View {
  let translation: TranslateOut

  var body: some View {
    let arrived = if case .text = translation.backTranslation { true } else { false }
    TintedBlock(label: WritingStrings.backTranslation, tone: arrived ? .accent : .neutral) {
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

/// The validation's issues in a warning block, one line each.
struct IssueList: View {
  let issues: [RewriteIssue]

  var body: some View {
    TintedBlock(tone: .warning) {
      ForEach(issues, id: \.self) { issue in
        HStack(alignment: .firstTextBaseline, spacing: Spacing.buttons) {
          Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
          Text(WritingStrings.issue(issue))
            .lineSpacing(Typography.secondary.lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .font(Typography.secondary.font)
      .foregroundStyle(Tone.warning.onTint)
    }
  }
}

// MARK: Diff

/// The proofread text with each change in place. An accepted change shows the removed
/// words struck through in red and the inserted ones in green on a rounded tint; a declined
/// one shows the original words thinly underlined, then the declined suggestion struck
/// through and faint. A plain space keeps the two sides from running together. The current
/// change, the one ← → and Space act on, is underlined in the accent colour. Every character
/// of a change carries its index (`.dictChange`) for clicks, and the pointing hand.
///
/// - Parameter accepted: The accepted changes; nil accepts every one.
@MainActor
func diffText(
  _ segments: [DiffSegment], accepted: Set<Int>? = nil, current: Int? = nil
) -> NSAttributedString {
  let red = DiffColor.removed
  let green = DiffColor.inserted
  let paragraph = NSMutableParagraphStyle()
  paragraph.lineSpacing = Typography.proofread.lineSpacing
  let base: [NSAttributedString.Key: Any] = [
    .font: Typography.proofread.nsFont, .foregroundColor: Palette.textPrimary,
    .paragraphStyle: paragraph,
  ]
  let text = NSMutableAttributedString()
  /// Appends `run`; the strike-through, underline or tint in `mark` leaves out the spaces
  /// at its ends, so it does not run into the next word.
  func append(
    _ run: String, _ attributes: [NSAttributedString.Key: Any],
    marking mark: [NSAttributedString.Key: Any]
  ) {
    let start = text.length
    text.append(NSAttributedString(string: run, attributes: attributes))
    let words = run.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !words.isEmpty else { return }
    let offset = (run as NSString).range(of: words).location
    text.addAttributes(
      mark, range: NSRange(location: start + offset, length: (words as NSString).length))
  }
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
      marked[.dictUnderline] = Palette.accent
    }
    if !from.isEmpty {
      var removed = marked
      var mark: [NSAttributedString.Key: Any] = [:]
      if isAccepted {
        removed[.foregroundColor] = red
        mark = [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: red]
      } else if !isCurrent {
        // The kept words, thinly underlined: they can be clicked to accept the change.
        mark = [
          .underlineStyle: NSUnderlineStyle.single.rawValue,
          .underlineColor: Palette.textTertiary,
        ]
      }
      append(from, removed, marking: mark)
    }
    if !from.isEmpty && !to.isEmpty {
      // Underlined with the change when current, so the change reads as one piece.
      text.append(NSAttributedString(string: " ", attributes: marked))
    }
    if !to.isEmpty {
      var inserted = marked
      let mark: [NSAttributedString.Key: Any]
      if isAccepted {
        inserted[.foregroundColor] = green
        mark = [.dictTint: DiffColor.insertedTint]
      } else {
        inserted[.foregroundColor] = Palette.textTertiary
        mark = [
          .strikethroughStyle: NSUnderlineStyle.single.rawValue,
          .strikethroughColor: Palette.textTertiary,
        ]
      }
      append(to, inserted, marking: mark)
    }
    change += 1
  }
  return text
}

extension NSAttributedString.Key {
  /// The index of the change a character of the diff belongs to (`diffText`).
  static let dictChange = NSAttributedString.Key("DictChange")
  /// A colour drawn behind the characters as a rounded box as tall as the font
  /// (`DiffLayoutManager`), where `.backgroundColor` fills the whole line.
  static let dictTint = NSAttributedString.Key("DictTint")
  /// A colour drawn as a bar under the characters, below the descenders and the tint, in
  /// one piece across runs of different colours, where `.underlineStyle` is cut at each.
  static let dictUnderline = NSAttributedString.Key("DictUnderline")
}

/// Draws the diff's marks behind its text: `.dictTint` as a box from the font's ascender to
/// its descender, a little wider than the words, with rounded corners, and `.dictUnderline`
/// as a bar under it. Text without them draws as in any text view.
final class DiffLayoutManager: NSLayoutManager {
  private static let padding: CGFloat = 2
  private static let radius: CGFloat = 3
  private static let underline: CGFloat = 2

  override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
    super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
    forEachLine(of: .dictTint, in: characters) { words, baseline, font in
      let box = CGRect(
        x: words.minX - Self.padding, y: baseline - font.ascender - 1,
        width: words.width + 2 * Self.padding, height: font.ascender - font.descender + 2)
      NSBezierPath(
        roundedRect: box.offsetBy(dx: origin.x, dy: origin.y), xRadius: Self.radius,
        yRadius: Self.radius
      ).fill()
    }
    forEachLine(of: .dictUnderline, in: characters) { words, baseline, font in
      let bar = CGRect(
        x: words.minX, y: baseline - font.descender + 2, width: words.width,
        height: Self.underline)
      bar.offsetBy(dx: origin.x, dy: origin.y).fill()
    }
  }

  /// Sets the fill to each run of `key`'s colour, then calls `draw` with the run's bounds on
  /// each line it falls on, the line's baseline and the run's font.
  private func forEachLine(
    of key: NSAttributedString.Key, in characters: NSRange,
    draw: @escaping (_ words: CGRect, _ baseline: CGFloat, _ font: NSFont) -> Void
  ) {
    guard let storage = textStorage else { return }
    storage.enumerateAttribute(key, in: characters) { value, range, _ in
      guard let color = value as? NSColor,
        let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
      else { return }
      color.setFill()
      let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      enumerateLineFragments(forGlyphRange: glyphs) { line, _, container, lineGlyphs, _ in
        let part = NSIntersectionRange(glyphs, lineGlyphs)
        guard part.length > 0 else { return }
        draw(
          self.boundingRect(forGlyphRange: part, in: container),
          line.minY + self.location(forGlyphAt: part.location).y, font)
      }
    }
  }
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
