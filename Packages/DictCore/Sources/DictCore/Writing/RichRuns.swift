// SPDX-License-Identifier: GPL-3.0-or-later

/// The formatting a replacement keeps (architecture 4.7), whatever the app encodes it as:
/// fonts, sizes and paragraph styles are left to the target.
public struct RunStyle: Hashable, Sendable {
  public var bold = false
  public var italic = false
  public var underline = false
  public var strike = false
  public var link: String?
  /// `#rrggbb`; nil for the editor's own text color.
  public var color: String?

  public init(
    bold: Bool = false, italic: Bool = false, underline: Bool = false, strike: Bool = false,
    link: String? = nil, color: String? = nil
  ) {
    self.bold = bold
    self.italic = italic
    self.underline = underline
    self.strike = strike
    self.link = link
    self.color = color
  }

  /// "B,I,U,S,L=<url>,C=<color>", in that order, for logs and tests.
  public var flags: String {
    var parts: [String] = []
    if bold { parts.append("B") }
    if italic { parts.append("I") }
    if underline { parts.append("U") }
    if strike { parts.append("S") }
    if let link { parts.append("L=\(link)") }
    if let color { parts.append("C=\(color)") }
    return parts.joined(separator: ",")
  }
}

/// Text with one style.
public struct StyledRun: Equatable, Sendable {
  public var text: String
  public var style: RunStyle

  public init(_ text: String, _ style: RunStyle = RunStyle()) {
    self.text = text
    self.style = style
  }
}

/// Neighbouring runs with the same style joined, and empty runs dropped.
public func mergedRuns(_ runs: [StyledRun]) -> [StyledRun] {
  var merged: [StyledRun] = []
  for run in runs where !run.text.isEmpty {
    if let last = merged.last, last.style == run.style {
      merged[merged.count - 1].text += run.text
    } else {
      merged.append(run)
    }
  }
  return merged
}

/// Whether the runs carry formatting worth keeping: any bold, italic, underline,
/// strikethrough or link, or more than one color. One color throughout is the editor's
/// theme or a rendering color (VS Code copies its theme color, measured), not a choice.
public func carriesFormatting(_ runs: [StyledRun]) -> Bool {
  let styles = runs.filter { !$0.text.isEmpty }.map(\.style)
  let marked = styles.contains {
    $0.bold || $0.italic || $0.underline || $0.strike || $0.link != nil
  }
  return marked || Set(styles.map(\.color)).count > 1
}

/// "[plain][bold]{B}[link]{L=…}", line breaks as ⏎, for logs and tests.
public func describeRuns(_ runs: [StyledRun]) -> String {
  mergedRuns(runs).map { run in
    let text = run.text.replacingOccurrences(of: "\n", with: "⏎")
    let flags = run.style.flags
    return flags.isEmpty ? "[\(text)]" : "[\(text)]{\(flags)}"
  }.joined()
}

/// A small semantic HTML fragment for the pasteboard: `<b>`, `<i>`, `<u>`, `<s>`,
/// `<a href>` and colored `<span>`, with no fonts or sizes, so the target keeps its own.
/// Paragraphs become `<p>` only when the text spans more than one: a replacement inside a
/// paragraph stays inline and cannot split it (measured in WebKit).
public func semanticHTML(_ runs: [StyledRun]) -> String {
  var paragraphs: [[StyledRun]] = [[]]
  for run in runs {
    let lines = run.text.split(separator: "\n", omittingEmptySubsequences: false)
    for (index, line) in lines.enumerated() {
      if index > 0 { paragraphs.append([]) }
      paragraphs[paragraphs.count - 1].append(StyledRun(String(line), run.style))
    }
  }
  let body =
    paragraphs.count == 1
    ? inlineHTML(paragraphs[0])
    : paragraphs.map { paragraph in
      let html = inlineHTML(paragraph)
      return "<p>\(html.isEmpty ? "<br>" : html)</p>"
    }.joined()
  return "<meta charset=\"utf-8\">" + body
}

private func inlineHTML(_ runs: [StyledRun]) -> String {
  var html = ""
  var openLink: String?
  for run in mergedRuns(runs) {
    let style = run.style
    if style.link != openLink {
      if openLink != nil { html += "</a>" }
      if let link = style.link { html += "<a href=\"\(escaped(link))\">" }
      openLink = style.link
    }
    // A link's color and underline are how the source rendered it, not the author's choice.
    var text = escaped(run.text)
    if let color = style.color, style.link == nil {
      text = "<span style=\"color:\(color)\">\(text)</span>"
    }
    if style.strike { text = "<s>\(text)</s>" }
    if style.underline && style.link == nil { text = "<u>\(text)</u>" }
    if style.italic { text = "<i>\(text)</i>" }
    if style.bold { text = "<b>\(text)</b>" }
    html += text
  }
  if openLink != nil { html += "</a>" }
  return html
}

private func escaped(_ text: String) -> String {
  text.replacingOccurrences(of: "&", with: "&amp;")
    .replacingOccurrences(of: "<", with: "&lt;")
    .replacingOccurrences(of: ">", with: "&gt;")
    .replacingOccurrences(of: "\"", with: "&quot;")
}
