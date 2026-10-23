// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import NaturalLanguage

/// Decides on the device which language a selection is translated into (architecture 5.2).
///
/// Only letters and ideographs count; digits, punctuation, symbols and emoji are ignored.
/// - No letters at all: `.undecided`.
/// - Less than a third of the letters in my language's script: `.intoMine`. This covers
///   the learning language when the scripts differ, and any third language in another script.
/// - Different scripts otherwise: `.intoLearning`, so mixed text such as
///   "这个 PR 我已经 review 过了" goes into the learning language. The exception is a third
///   language written in my script, such as Japanese with many kanji for a Chinese speaker:
///   when the recognizer, limited to the languages of my script, is more than 80% sure of
///   it, the text goes `.intoMine`.
/// - Same script (Spanish and English, Simplified and Traditional Chinese): the language
///   recognizer, limited to the two languages, decides when it is more than 80% sure;
///   otherwise `.undecided`.
public func resolveDirection(_ text: String, pair: LanguagePair) -> Direction {
  let mineScripts = WritingScript.scripts(of: pair.mine)
  let letters = text.unicodeScalars.filter(\.properties.isAlphabetic)
  guard !letters.isEmpty, !mineScripts.isEmpty else { return .undecided }

  let mineCount = letters.count { WritingScript.of($0).map(mineScripts.contains) ?? false }
  guard 3 * mineCount >= letters.count else { return .intoMine }
  guard mineScripts == WritingScript.scripts(of: pair.learning) else {
    return isThirdLanguage(text, writtenIn: mineScripts, pair: pair) ? .intoMine : .intoLearning
  }
  return recognizedDirection(text, pair: pair)
}

/// Languages the recognizer chooses from when text in my script may be a third language,
/// keyed by script. Only scripts shared by several common languages are listed.
private let languagesSharingScript: [WritingScript: [NLLanguage]] = [
  .han: [.simplifiedChinese, .traditionalChinese, .japanese],
  .latin: [.english, .french, .german, .spanish, .italian, .portuguese, .dutch],
  .cyrillic: [.russian, .ukrainian, .bulgarian],
]

/// Whether the recognizer, limited to the languages sharing my script, is more than 80% sure
/// the text is in a language that is neither of the pair.
private func isThirdLanguage(
  _ text: String, writtenIn scripts: Set<WritingScript>, pair: LanguagePair
) -> Bool {
  let candidates = Set(scripts.flatMap { languagesSharingScript[$0] ?? [] })
  guard candidates.count > 1 else { return false }
  let recognizer = NLLanguageRecognizer()
  recognizer.languageConstraints = Array(candidates)
  recognizer.processString(text)
  guard
    let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
    confidence > 0.8
  else { return false }
  let code = Locale.Language(identifier: language.rawValue).languageCode
  return code != pair.mine.languageCode && code != pair.learning.languageCode
}

private func recognizedDirection(_ text: String, pair: LanguagePair) -> Direction {
  let mine = recognizerLanguage(pair.mine)
  let learning = recognizerLanguage(pair.learning)
  guard mine != learning else { return .undecided }

  let recognizer = NLLanguageRecognizer()
  recognizer.languageConstraints = [mine, learning]
  recognizer.processString(text)
  guard
    let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
    confidence > 0.8
  else { return .undecided }
  return language == mine ? .intoLearning : .intoMine
}

/// The recognizer tells Chinese apart by script and every other language by its code.
private func recognizerLanguage(_ language: Locale.Language) -> NLLanguage {
  guard language.languageCode == .chinese else {
    return NLLanguage(rawValue: language.languageCode?.identifier ?? language.minimalIdentifier)
  }
  let script = Locale.Language(identifier: language.maximalIdentifier).script
  return script == .hanTraditional ? .traditionalChinese : .simplifiedChinese
}
