// SPDX-License-Identifier: GPL-3.0-or-later
//
// Replacing with the source's formatting kept (architecture 4.7): the corrected or
// translated text takes the source's bold, italic, links and colors through the diff, and is
// pasted as plain text, RTF and HTML together. Anything that cannot be done safely is plain
// text, as before, for a reason the log names.

import AppKit
import DictCore

/// Formatted text captured with a selection. The attributed string is an immutable copy.
enum RichSource: @unchecked Sendable, Equatable {
  /// Read through `AXAttributedStringForRange`, with AppKit attributes; its text is the
  /// selection's.
  case accessibility(NSAttributedString)
  /// The richest flavor a copy left on the clipboard: RTFD, RTF or HTML.
  case pasteboard(NSPasteboard.PasteboardType, Data)

  /// The formatted text; HTML is read through WebKit, so only on the main thread.
  @MainActor var attributed: NSAttributedString? {
    switch self {
    case .accessibility(let text):
      return text
    case .pasteboard(let type, let data):
      let documentType: NSAttributedString.DocumentType =
        switch type {
        case .rtfd: .rtfd
        case .html: .html
        default: .rtf
        }
      return try? NSAttributedString(
        data: data,
        options: [.documentType: documentType, .characterEncoding: String.Encoding.utf8.rawValue],
        documentAttributes: nil)
    }
  }
}

/// What goes on the clipboard beside the plain text: RTF for native text views, a small
/// semantic HTML for web views (architecture 4.7).
struct RichPayload: Sendable, Equatable {
  let rtf: Data
  let html: String
  /// Which formats it holds, "B,I,U,S,L,C", for the log: no text, no link targets.
  let summary: String

  init?(_ text: NSAttributedString) {
    let range = NSRange(location: 0, length: text.length)
    guard let rtf = text.rtf(from: range, documentAttributes: [:]) else { return nil }
    let styles = styledRuns(text).map(\.style)
    self.rtf = rtf
    html = semanticHTML(styledRuns(text))
    let marks: [(String, (RunStyle) -> Bool)] = [
      ("B", \.bold), ("I", \.italic), ("U", \.underline), ("S", \.strike),
      ("L", { $0.link != nil }), ("C", { $0.color != nil }),
    ]
    summary = marks.filter { _, has in styles.contains(where: has) }.map(\.0)
      .joined(separator: ",")
  }
}

/// Why a replacement is plain text, in the order they are checked (architecture 4.7).
enum PlainReason: String, Sendable, Equatable, CaseIterable {
  /// The "keep formatting" setting is off.
  case settingOff
  /// Nothing formatted was captured, or it cannot be read.
  case noRichSource
  /// Accessibility reports only part of this app's formatting (Chromium and Electron: color
  /// and underline at most; Notes: no bold, measured), so pasting it would lose the rest.
  case incompleteSource
  /// The app takes plain text only (code editors, terminals): formatting would do nothing.
  case plainTextTarget
  /// The formatted text is not the text that was corrected or translated.
  case textMismatch
  /// No bold, italic, underline, strikethrough or link, and at most one color, in the
  /// source or in what carries over: plain text is as good, and can be written through
  /// accessibility.
  case nothingToKeep
  /// The diff does not spell out the source.
  case carryFailed
  /// A Chromium app and a result across paragraphs: paragraphs come first (architecture
  /// 3.9, 16.1 item 2).
  case chromiumParagraphs
}

enum RichDecision: Equatable {
  case rich(RichPayload)
  case plain(PlainReason)
}

/// Apps whose text views take plain text only, whatever the clipboard holds (VS Code
/// measured), besides terminals.
let plainTextEditors: Set<String> = [
  "com.microsoft.VSCode",
  "com.microsoft.VSCodeInsiders",
  "com.vscodium",
  "com.todesktop.230313mzl4w4u92",  // Cursor
  "dev.zed.Zed",
  "com.apple.dt.Xcode",
  "com.sublimetext.4",
]

/// Native apps whose accessibility formatting is incomplete (Notes: no bold, measured).
let incompleteAccessibilityFormatting: Set<String> = ["com.apple.Notes"]

/// Whether to replace with formatting, and with what: `source` is what the capture read,
/// `text` what was corrected or translated, and `segments` the diff from `text` to the
/// result, the accepted changes only. Rows 8 and 9 of the spike's table, reading back, are
/// the writer's.
@MainActor
func richReplacement(
  enabled: Bool, source: RichSource?, text: String, segments: [DiffSegment], app: TargetApp
) -> RichDecision {
  guard enabled else { return .plain(.settingOff) }
  guard let source else { return .plain(.noRichSource) }
  if case .accessibility = source,
    app.kind != .native || app.bundleID.map(incompleteAccessibilityFormatting.contains) == true
  {
    return .plain(.incompleteSource)
  }
  if app.kind == .terminal || app.bundleID.map(plainTextEditors.contains) == true {
    return .plain(.plainTextTarget)
  }
  guard let attributed = source.attributed else { return .plain(.noRichSource) }
  guard let aligned = aligned(attributed, to: text) else { return .plain(.textMismatch) }
  guard carriesFormatting(styledRuns(aligned)) else { return .plain(.nothingToKeep) }
  guard let carried = carryAttributes(from: aligned, along: segments) else {
    return .plain(.carryFailed)
  }
  guard carriesFormatting(styledRuns(carried)) else { return .plain(.nothingToKeep) }
  if app.kind == .chromium, carried.string.contains("\n") {
    return .plain(.chromiumParagraphs)
  }
  guard let payload = RichPayload(carried) else { return .plain(.carryFailed) }
  return .rich(payload)
}

/// `source` with the text `text` has: as it is, or with line endings unified and the
/// trailing line break a copy adds removed, or also with no-break spaces as spaces (WebKit).
func aligned(_ source: NSAttributedString, to text: String) -> NSAttributedString? {
  if source.string == text { return source }
  let unified = NSMutableAttributedString(attributedString: source)
  replace(in: unified, "\r\n", with: "\n")
  replace(in: unified, "\u{2029}", with: "\n")
  while unified.string.hasSuffix("\n"), !text.hasSuffix("\n") {
    unified.deleteCharacters(in: NSRange(location: unified.length - 1, length: 1))
  }
  if unified.string == text { return unified }
  replace(in: unified, "\u{00A0}", with: " ")
  return unified.string == text ? unified : nil
}

private func replace(in text: NSMutableAttributedString, _ target: String, with replacement: String)
{
  text.mutableString.replaceOccurrences(
    of: target, with: replacement, range: NSRange(location: 0, length: text.length))
}

// MARK: - Reading the formatting

/// The formatting of AppKit attributes that a replacement keeps.
func runStyle(_ attributes: [NSAttributedString.Key: Any]) -> RunStyle {
  var style = RunStyle()
  if let font = attributes[.font] as? NSFont {
    let traits = font.fontDescriptor.symbolicTraits
    style.bold = traits.contains(.bold)
    style.italic = traits.contains(.italic)
  }
  style.underline = ((attributes[.underlineStyle] as? Int) ?? 0) != 0
  style.strike = ((attributes[.strikethroughStyle] as? Int) ?? 0) != 0
  switch attributes[.link] {
  case let url as URL: style.link = url.absoluteString
  case let string as String: style.link = string
  default: break
  }
  style.color = (attributes[.foregroundColor] as? NSColor).flatMap(hexColor)
  return style
}

func styledRuns(_ text: NSAttributedString) -> [StyledRun] {
  var runs: [StyledRun] = []
  text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
    runs.append(StyledRun((text.string as NSString).substring(with: range), runStyle(attributes)))
  }
  return mergedRuns(runs)
}

/// `#rrggbb` in sRGB, or nil for near-black and near-white: the editor's own text color in
/// either appearance, not the author's choice.
func hexColor(_ color: NSColor) -> String? {
  guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
  let channels = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
  guard let brightest = channels.max(), let darkest = channels.min(),
    brightest >= 0.2, darkest <= 0.9
  else { return nil }
  return channels.map { String(format: "%02x", Int((min(max($0, 0), 1) * 255).rounded())) }
    .reduce("#", +)
}
