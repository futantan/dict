// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The dictionary key. Must stay identical to `DictCore.normalizedKey` (architecture 5.3):
/// NFKC, lowercased, trimmed, inner whitespace collapsed to one space.
public func normalizedKey(_ text: String) -> String {
  text.precomposedStringWithCompatibilityMapping
    .lowercased()
    .split(whereSeparator: \.isWhitespace)
    .joined(separator: " ")
}

/// Traditional to Simplified Chinese with ICU's character-level transform, which ships with
/// the system. Latin text passes through unchanged.
public func toSimplified(_ text: String) -> String {
  text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
}

/// True when the text contains at least one Han ideograph.
public func containsHan(_ text: String) -> Bool {
  text.unicodeScalars.contains { $0.properties.isIdeographic }
}

/// Cleans one Wiktionary gloss into a short Simplified Chinese definition, or returns nil
/// when nothing usable is left: no Chinese at all, leftover wiki markup, or a bare pointer to
/// another entry ("child 的複數", "colour的另一種寫法") that belongs in the form table instead.
public func cleanGloss(_ raw: String) -> String? {
  // A template anywhere means a placeholder such as {{rfdef}} ("needs a translation").
  if raw.contains("{{") { return nil }
  // Later lines are extraction residue: "====翻译====" sections, "* 正體:" variants, examples.
  guard let firstLine = raw.split(whereSeparator: \.isNewline).first else { return nil }
  var gloss = String(firstLine)
  if ["}}", "[[", "]]", "<!--", "==="].contains(where: gloss.contains) { return nil }
  gloss = toSimplified(gloss)
    .replacingOccurrences(of: "﹝", with: "（")
    .replacingOccurrences(of: "﹞", with: "）")
    .replacingOccurrences(of: "［", with: "（")
    .replacingOccurrences(of: "］", with: "）")
    .replacing(#"<([^<>]{1,12})>"#, with: "（$1）", when: "<")
    // Learner-dictionary grammar codes: [U] [C] [T] [I] [S1].
    .replacing(#"\[[A-Z][A-Za-z0-9]{0,2}\]"#, with: "", when: "[")
    .replacing(#"\[([^\[\]]{1,12})\]"#, with: "（$1）", when: "[")
    .replacing(#"(?<=\p{Han});(?=\p{Han})"#, with: "；", when: ";")
    .split(whereSeparator: \.isWhitespace).joined(separator: " ")
  if gloss.contains("Template:") {
    guard let unlabelled = expandingTemplateLabel(gloss) else { return nil }
    gloss = unlabelled
  }
  gloss = gloss.trimmingCharacters(in: glossEdgeTrim)
  guard containsHan(withoutParentheses(gloss)), !isPointerGloss(gloss) else { return nil }
  return gloss
}

extension String {
  /// Regular-expression replacement, skipped when the text lacks `trigger` (most glosses
  /// need none of the rewrites, and regex matching dominates the build time otherwise).
  fileprivate func replacing(_ pattern: String, with template: String, when trigger: String)
    -> String
  {
    guard contains(trigger) else { return self }
    return replacingOccurrences(of: pattern, with: template, options: .regularExpression)
  }
}

/// Unexpanded label templates leak into some glosses as ":Template:计算机 服务器" or
/// "创建（:Template:之过去式）". A topic label becomes a parenthesized prefix, countability
/// labels are dropped, and a template that was the whole definition leaves nothing (nil).
private func expandingTemplateLabel(_ gloss: String) -> String? {
  var text = gloss.replacingOccurrences(
    of: #"[（(][^（）()]*Template:[^（）()]*[）)]"#, with: "", options: .regularExpression)
  if let match = text.firstMatch(of: /^\s*:?Template:(\S+)\s*/) {
    let label = String(match.1)
    let rest = String(text[match.range.upperBound...])
    if label.hasPrefix("之") || rest.isEmpty { return nil }
    text = ["可数", "不可数"].contains(label) ? rest : "（\(label)）\(rest)"
  }
  return text.contains("Template:") ? nil : text
}

/// The text with parenthesized asides removed, so "troll (复数 trolls)" counts as having no
/// Chinese definition.
private func withoutParentheses(_ text: String) -> String {
  text.replacingOccurrences(of: #"\([^)]*\)|（[^）]*）"#, with: "", options: .regularExpression)
}

private let glossEdgeTrim = CharacterSet.whitespaces.union(
  CharacterSet(charactersIn: "。．.；;，,：:、"))

/// Glosses that only say "this is an inflection or spelling of another word". They arrive in
/// Simplified form, so only the simplified wording is matched.
private func isPointerGloss(_ gloss: String) -> Bool {
  gloss.range(of: pointerGlossPattern, options: .regularExpression) != nil
}

private let pointerGlossPattern =
  #"^[^\p{Han}]+ ?(\([^)]*\)|（[^）]*）)? ?(之|的)"#
  + #"(复数|另一|过去|一般过去|现在分词|第三人称|单数第三人称|比较级|最高级|同义词|异体|变体|旧|古|罕见|"#
  + #"非正式写法|非标准|拼写错误|错拼|弃用|小写形|大写形|首字母小写|首字母大写|受审查|绕过)"#

/// Maps a wiktextract part of speech onto the model card's enum (architecture 6.x): noun, verb,
/// adjective, adverb, preposition, conjunction, pronoun, determiner, interjection,
/// phrasal verb, idiom, phrase, abbreviation, or "" when none fits.
public func partOfSpeech(_ pos: String, word: String) -> String {
  switch pos {
  case "noun", "name": "noun"
  case "verb": word.contains(" ") ? "phrasal verb" : "verb"
  case "adj": "adjective"
  case "adv": "adverb"
  case "prep", "postp": "preposition"
  case "conj": "conjunction"
  case "pron": "pronoun"
  case "det", "article": "determiner"
  case "intj": "interjection"
  case "proverb": "idiom"
  case "phrase", "prep_phrase": "phrase"
  case "abbrev", "contraction": "abbreviation"
  default: ""
  }
}
