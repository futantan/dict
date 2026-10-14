// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices

/// The longest selection whose formatting is read: past it, a replacement is plain text.
let maxFormattedLength = 20_000

/// The selection's formatting through `AXAttributedStringForRange`, as AppKit attributes,
/// or nil when the element does not answer or answers other text (architecture 4.7).
/// Accessibility queue only.
func readFormattedSelection(_ element: AXUIElement, range: CFRange, text: String)
  -> NSAttributedString?
{
  guard range.length > 0, range.length <= maxFormattedLength,
    let parameter = AX.rangeValue(range),
    let value = AX.value(element, "AXAttributedStringForRange", parameter: parameter).1
      as? NSAttributedString
  else { return nil }
  let formatted = formattedText(fromAccessibility: value) { link in
    guard let link = AX.asElement(link) else { return nil }
    switch AX.value(link, kAXURLAttribute).1 {
    case let url as URL: return url
    case let string as String: return URL(string: string)
    default: return nil
    }
  }
  return formatted.string == text ? formatted : nil
}

/// An accessibility attributed string with AppKit's attributes in place of the
/// accessibility ones: font, a chosen text color, underline, strikethrough and link. Spelling
/// marks and alignment are dropped. `linkURL` resolves an `AXLink` value, an element.
func formattedText(
  fromAccessibility value: NSAttributedString, linkURL: (CFTypeRef) -> URL?
) -> NSAttributedString {
  let result = NSMutableAttributedString(string: value.string)
  value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { ax, range, _ in
    var attributes: [NSAttributedString.Key: Any] = [:]
    if let font = (ax[.init("AXFont")] as? [String: Any]).flatMap(font(fromAccessibility:)) {
      attributes[.font] = font
    }
    if let color = ax[.init("AXForegroundColor")].flatMap(chosenColor) {
      attributes[.foregroundColor] = color
    }
    if isOn(ax[.init("AXUnderline")]) {
      attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
    }
    if isOn(ax[.init("AXStrikethrough")]) {
      attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
    }
    if let link = ax[.init("AXLink")], let url = linkURL(link as CFTypeRef) {
      attributes[.link] = url
    }
    result.setAttributes(attributes, range: range)
  }
  return result
}

/// The font an `AXFont` dictionary names. System fonts are rebuilt from their weight and
/// slant: their private names (".SFNS-RegularItalic") do not resolve by name.
private func font(fromAccessibility font: [String: Any]) -> NSFont? {
  guard let name = font["AXFontName"] as? String else { return nil }
  let size = (font["AXFontSize"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 13
  let described = name + " " + (font["AXVisibleName"] as? String ?? "")
  let bold = ["Bold", "Heavy", "Black"].contains { described.contains($0) }
  let italic = ["Italic", "Oblique"].contains { described.contains($0) }
  var result =
    name.hasPrefix(".")
    ? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    : NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
  var traits = result.fontDescriptor.symbolicTraits
  if bold { traits.insert(.bold) }
  if italic { traits.insert(.italic) }
  if traits != result.fontDescriptor.symbolicTraits,
    let styled = NSFont(descriptor: result.fontDescriptor.withSymbolicTraits(traits), size: size)
  {
    result = styled
  }
  return result
}

/// The text color, or nil for near-black and near-white: the editor's own color, resolved
/// for the current appearance. Accessibility labels the color Generic RGB but reports the
/// sRGB components (measured: #cc0000 arrives as 0.8, 0, 0), so they are read as sRGB.
private func chosenColor(_ value: Any) -> NSColor? {
  guard CFGetTypeID(value as CFTypeRef) == CGColor.typeID else { return nil }
  // swift-format-ignore: NeverForceUnwrap
  let color = value as! CGColor  // Checked by type ID above.
  guard let components = color.components, components.count >= 3 else { return nil }
  let srgb = NSColor(
    srgbRed: components[0], green: components[1], blue: components[2], alpha: color.alpha)
  return hexColor(srgb) == nil ? nil : srgb
}

private func isOn(_ value: Any?) -> Bool {
  (value as? NSNumber).map { $0.intValue != 0 } ?? false
}
