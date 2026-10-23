// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import Testing

@testable import DictApp

private let docs = URL(string: "https://example.com/docs") ?? URL(filePath: "/")
private var regular: NSFont { NSFont.systemFont(ofSize: 13) }
private var bold: NSFont { NSFont.boldSystemFont(ofSize: 13) }
private let red = NSColor(srgbRed: 0.8, green: 0, blue: 0, alpha: 1)

/// "Ths is a **bold wrd** and [a lnk here](docs).⏎Second paragraf <red>red</red> end."
private func fixture() -> NSAttributedString {
  let text = NSMutableAttributedString()
  func add(_ string: String, _ attributes: [NSAttributedString.Key: Any] = [:]) {
    text.append(
      NSAttributedString(string: string, attributes: [.font: regular].merging(attributes) { $1 }))
  }
  add("Ths is a ")
  add("bold wrd", [.font: bold])
  add(" and ")
  add("a lnk here", [.link: docs])
  add(".\nSecond paragraf ")
  add("red", [.foregroundColor: red])
  add(" end.")
  return text
}

private let fixtureEdits = [
  Edit(kind: .spelling, wrong: "Ths", right: "This"),
  Edit(kind: .spelling, wrong: "wrd", right: "word"),
  Edit(kind: .spelling, wrong: "lnk", right: "link"),
  Edit(kind: .spelling, wrong: "paragraf", right: "paragraph"),
]

private let textEdit = TargetApp(
  pid: 42, bundleID: "com.apple.TextEdit", launchDate: nil, kind: .native)

@MainActor
private func decide(
  _ source: RichSource?, text: String? = nil, segments: [DiffSegment]? = nil,
  app: TargetApp = textEdit, enabled: Bool = true
) throws -> RichDecision {
  let text = text ?? fixture().string
  let segments = try segments ?? applyEdits(fixtureEdits, to: text).get().segments
  return richReplacement(
    enabled: enabled, source: source, text: text, segments: segments, app: app)
}

/// The decision of architecture 4.7, row by row, and the formatting it pastes.
@MainActor
struct RichReplaceTests {
  @Test func aCorrectionOfFormattedTextKeepsEveryFormat() throws {
    guard case .rich(let payload) = try decide(.accessibility(fixture())) else {
      Issue.record("expected formatting")
      return
    }
    let pasted = try #require(NSAttributedString(rtf: payload.rtf, documentAttributes: nil))
    #expect(pasted.string == "This is a bold word and a link here.\nSecond paragraph red end.")
    #expect(
      describeRuns(styledRuns(pasted))
        == "[This is a ][bold word]{B}[ and ][a link here]{L=https://example.com/docs}"
        + "[.⏎Second paragraph ][red]{C=#cc0000}[ end.]")
    #expect(
      payload.html
        == "<meta charset=\"utf-8\"><p>This is a <b>bold word</b> and "
        + "<a href=\"https://example.com/docs\">a link here</a>.</p>"
        + "<p>Second paragraph <span style=\"color:#cc0000\">red</span> end.</p>")
  }

  @Test func theSettingOffIsPlainText() throws {
    #expect(try decide(.accessibility(fixture()), enabled: false) == .plain(.settingOff))
  }

  @Test func nothingCapturedIsPlainText() throws {
    #expect(try decide(nil) == .plain(.noRichSource))
  }

  @Test func anUnreadableClipboardFlavorIsPlainText() throws {
    #expect(try decide(.pasteboard(.rtf, Data("not rtf".utf8))) == .plain(.noRichSource))
  }

  @Test(arguments: [
    TargetApp(pid: 1, bundleID: "com.google.Chrome", launchDate: nil, kind: .chromium),
    TargetApp(pid: 1, bundleID: "com.tinyspeck.slackmacgap", launchDate: nil, kind: .electron),
    TargetApp(pid: 1, bundleID: "com.apple.Notes", launchDate: nil, kind: .native),
  ])
  func accessibilityFormattingThatMissesFormatsIsPlainText(app: TargetApp) throws {
    #expect(try decide(.accessibility(fixture()), app: app) == .plain(.incompleteSource))
  }

  @Test(arguments: [
    TargetApp(pid: 1, bundleID: "com.microsoft.VSCode", launchDate: nil, kind: .electron),
    TargetApp(pid: 1, bundleID: "com.apple.Terminal", launchDate: nil, kind: .terminal),
  ])
  func aPlainTextEditorGetsPlainText(app: TargetApp) throws {
    let rtf = try rtf(fixture())
    #expect(try decide(.pasteboard(.rtf, rtf), app: app) == .plain(.plainTextTarget))
  }

  @Test func formattedTextOfOtherTextIsPlainText() throws {
    let other = NSAttributedString(string: "Other text.", attributes: [.font: bold])
    #expect(try decide(.accessibility(other)) == .plain(.textMismatch))
  }

  /// A copy ends in a line break and may hold no-break spaces; the corrected text does not.
  @Test func aCopysTrailingLineBreakAndNoBreakSpacesAreAligned() throws {
    let copied = NSMutableAttributedString(attributedString: fixture())
    copied.mutableString.replaceOccurrences(
      of: " ", with: "\u{00A0}", range: NSRange(location: 0, length: 4))
    copied.append(NSAttributedString(string: "\r\n"))
    guard case .rich = try decide(.pasteboard(.rtf, try rtf(copied))) else {
      Issue.record("expected formatting")
      return
    }
  }

  @Test func textWithNoFormattingIsPlainText() throws {
    let plain = NSAttributedString(string: fixture().string, attributes: [.font: regular])
    #expect(try decide(.accessibility(plain)) == .plain(.nothingToKeep))
  }

  /// VS Code copies its theme color for the whole text (measured): one color is not a choice.
  @Test func oneColorThroughoutIsNoFormatting() throws {
    let themed = NSAttributedString(
      string: fixture().string,
      attributes: [
        .font: regular, .foregroundColor: NSColor(srgbRed: 0.73, green: 0.75, blue: 0.75, alpha: 1),
      ])
    #expect(try decide(.accessibility(themed)) == .plain(.nothingToKeep))
  }

  /// A translation is one change: only what all the source shares carries over.
  @Test func aTranslationOfMixedFormatsHasNothingToKeep() throws {
    let source = fixture()
    let decision = try decide(
      .accessibility(source),
      segments: [.changed(from: source.string, to: "Translated.\nSecond.")])
    #expect(decision == .plain(.nothingToKeep))
  }

  @Test func aTranslationOfBoldTextStaysBold() throws {
    let source = NSAttributedString(string: "我们明天开会。", attributes: [.font: bold])
    let decision = try decide(
      .accessibility(source), text: source.string,
      segments: [.changed(from: source.string, to: "We meet tomorrow.")])
    guard case .rich(let payload) = decision else {
      Issue.record("expected formatting")
      return
    }
    #expect(payload.html == "<meta charset=\"utf-8\"><b>We meet tomorrow.</b>")
  }

  @Test func segmentsThatDoNotSpellTheSourceArePlainText() throws {
    let decision = try decide(
      .accessibility(fixture()), segments: [.changed(from: "something else", to: "x")])
    #expect(decision == .plain(.carryFailed))
  }

  @Test func chromiumAcrossParagraphsIsPlainText() throws {
    let chrome = TargetApp(pid: 1, bundleID: "com.google.Chrome", launchDate: nil, kind: .chromium)
    #expect(
      try decide(.pasteboard(.rtf, try rtf(fixture())), app: chrome) == .plain(.chromiumParagraphs))
  }

  @Test func chromiumWithinAParagraphKeepsFormatting() throws {
    let chrome = TargetApp(pid: 1, bundleID: "com.google.Chrome", launchDate: nil, kind: .chromium)
    let line = fixture().attributedSubstring(from: NSRange(location: 0, length: 33))
    #expect(line.string == "Ths is a bold wrd and a lnk here.")
    let decision = try decide(
      .pasteboard(.rtf, try rtf(line)), text: line.string,
      segments: textDiff(line.string, "This is a bold word and a link here."), app: chrome)
    guard case .rich = decision else {
      Issue.record("expected formatting, got \(decision)")
      return
    }
  }

  /// Declined changes keep the source's text and formatting.
  @Test func onlyTheAcceptedChangesAreMadeAndEveryFormatStays() throws {
    let source = fixture()
    let applied = try applyEdits(fixtureEdits, to: source.string).get()
    guard
      case .rich(let payload) = try decide(
        .accessibility(source), segments: applied.accepting([1]).segments)
    else {
      Issue.record("expected formatting")
      return
    }
    let pasted = try #require(NSAttributedString(rtf: payload.rtf, documentAttributes: nil))
    #expect(
      describeRuns(styledRuns(pasted))
        == "[Ths is a ][bold word]{B}[ and ][a lnk here]{L=https://example.com/docs}"
        + "[.⏎Second paragraf ][red]{C=#cc0000}[ end.]")
  }

  @Test func nearBlackAndNearWhiteAreTheEditorsColor() {
    #expect(hexColor(.black) == nil)
    #expect(hexColor(.white) == nil)
    #expect(hexColor(NSColor(srgbRed: 0.1, green: 0.1, blue: 0.15, alpha: 1)) == nil)
    #expect(hexColor(red) == "#cc0000")
  }

  private func rtf(_ text: NSAttributedString) throws -> Data {
    try #require(text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:]))
  }
}

/// Accessibility's attributed string, as an `NSTextView` gives it in process (the same keys
/// another app's gives through `AXAttributedStringForRange`), back to AppKit attributes.
@MainActor
struct AccessibilityFormattingTests {
  @Test func boldItalicLinkColorUnderlineAndStrikethroughComeBack() throws {
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
    view.isRichText = true
    let source = NSMutableAttributedString(attributedString: fixture())
    let italic = NSFont(descriptor: regular.fontDescriptor.withSymbolicTraits(.italic), size: 13)
    source.append(NSAttributedString(string: " it", attributes: [.font: try #require(italic)]))
    source.append(
      NSAttributedString(
        string: " gone",
        attributes: [
          .font: try #require(NSFont(name: "Helvetica", size: 12)),
          .underlineStyle: NSUnderlineStyle.single.rawValue,
          .strikethroughStyle: NSUnderlineStyle.single.rawValue,
        ]))
    view.textStorage?.setAttributedString(source)
    let range = NSRange(location: 0, length: source.length)
    let accessibility = try #require(view.accessibilityAttributedString(for: range))
    var links = 0
    let text = formattedText(fromAccessibility: accessibility) { _ in
      links += 1
      return docs
    }
    #expect(text.string == source.string)
    #expect(
      describeRuns(styledRuns(text))
        == "[Ths is a ][bold wrd]{B}[ and ][a lnk here]{L=https://example.com/docs}"
        + "[.⏎Second paragraf ][red]{C=#cc0000}[ end.][ it]{I}[ gone]{U,S}")
    #expect(links == 1)
    let sizes = Set(styledFonts(text).map(\.pointSize))
    #expect(sizes == [12, 13])
  }

  private func styledFonts(_ text: NSAttributedString) -> [NSFont] {
    var fonts: [NSFont] = []
    text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, _, _ in
      if let font = value as? NSFont { fonts.append(font) }
    }
    return fonts
  }
}
