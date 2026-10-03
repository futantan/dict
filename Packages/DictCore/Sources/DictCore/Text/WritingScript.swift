// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A coarse script bucket for counting letters. Only the scripts of common language pairs are
/// listed; letters of any other script fall into none and never count as "my language".
enum WritingScript: Sendable, CaseIterable {
  case latin, greek, cyrillic, armenian, hebrew, arabic, devanagari, bengali, thai, georgian
  case hangul, hiragana, katakana, han

  /// Unicode blocks of each script, including fullwidth and halfwidth forms.
  var ranges: [ClosedRange<UInt32>] {
    switch self {
    case .latin:
      [
        0x0041...0x005A, 0x0061...0x007A, 0x00AA...0x00AA, 0x00BA...0x00BA, 0x00C0...0x02AF,
        0x1E00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF, 0xAB30...0xAB6F, 0xFF21...0xFF3A,
        0xFF41...0xFF5A,
      ]
    case .greek: [0x0370...0x03FF, 0x1F00...0x1FFF]
    case .cyrillic: [0x0400...0x052F, 0x1C80...0x1C8F, 0x2DE0...0x2DFF, 0xA640...0xA69F]
    case .armenian: [0x0530...0x058F, 0xFB13...0xFB17]
    case .hebrew: [0x0590...0x05FF, 0xFB1D...0xFB4F]
    case .arabic:
      [0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF]
    case .devanagari: [0x0900...0x097F, 0xA8E0...0xA8FF]
    case .bengali: [0x0980...0x09FF]
    case .thai: [0x0E00...0x0E7F]
    case .georgian: [0x10A0...0x10FF, 0x1C90...0x1CBF, 0x2D00...0x2D2F]
    case .hangul:
      [
        0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7FF, 0xFFA0...0xFFDC,
      ]
    case .hiragana: [0x3040...0x309F, 0x1B000...0x1B16F]
    case .katakana: [0x30A0...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F]
    case .han:
      [
        0x3005...0x3007, 0x3021...0x3029, 0x3038...0x303B, 0x3400...0x4DBF, 0x4E00...0x9FFF,
        0xF900...0xFAFF, 0x20000...0x3FFFF,
      ]
    }
  }

  /// The listed script a scalar belongs to, or nil.
  static func of(_ scalar: Unicode.Scalar) -> WritingScript? {
    allCases.first { script in script.ranges.contains { $0.contains(scalar.value) } }
  }

  /// The scripts a language is written in, keyed by ISO 15924 code; empty when unknown.
  static func scripts(of language: Locale.Language) -> Set<WritingScript> {
    let code = Locale.Language(identifier: language.maximalIdentifier).script?.identifier
    switch code {
    case "Latn": return [.latin]
    case "Grek": return [.greek]
    case "Cyrl": return [.cyrillic]
    case "Armn": return [.armenian]
    case "Hebr": return [.hebrew]
    case "Arab": return [.arabic]
    case "Deva": return [.devanagari]
    case "Beng": return [.bengali]
    case "Thai": return [.thai]
    case "Geor": return [.georgian]
    // Modern Korean is written in Hangul; counting Han would make Chinese text look Korean.
    case "Kore", "Hang": return [.hangul]
    case "Jpan": return [.han, .hiragana, .katakana]
    case "Hira": return [.hiragana]
    case "Kana": return [.katakana]
    case "Hani", "Hans", "Hant": return [.han]
    default: return []
    }
  }
}
