// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

/// A small seeded generator, so random splits are the same on every run.
private struct SplitMix64: RandomNumberGenerator {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

/// `text` cut at the given Unicode scalar offsets.
private func pieces(_ text: String, at cuts: [Int]) -> [String] {
  let scalars = Array(text.unicodeScalars)
  let bounds = [0] + cuts.sorted() + [scalars.count]
  return zip(bounds, bounds.dropFirst()).map { start, end in
    var piece = String.UnicodeScalarView()
    piece.append(contentsOf: scalars[start..<end])
    return String(piece)
  }
}

private func scanned(_ pieces: [String]) -> TopLevelFieldScanner {
  var scanner = TopLevelFieldScanner()
  for piece in pieces { scanner.feed(piece) }
  return scanner
}

/// Escapes, brackets inside strings, nested objects that reuse a top-level key name, a field
/// after the arrays, a number and a literal: everything the scanner has to step over.
private let tricky = #"""
  {"status":"ok","lemma":"say \"hi\"","phonetic":"/a\\b/","partOfSpeech":"verb",
   "definition":"经营 {x} [y] 中😀, \"q\"","otherSenses":[{"partOfSpeech":"noun",
   "definition":"nested, not top level"}],"examples":[],"count":3,"flag":true,"empty":"",
   "contextTranslation":"后来\n的"}
  """#

private let trickyValues = [
  "status": "ok", "lemma": #"say "hi""#, "phonetic": #"/a\b/"#, "partOfSpeech": "verb",
  "definition": #"经营 {x} [y] 中😀, "q""#, "empty": "", "contextTranslation": "后来\n的",
]

struct TopLevelFieldScannerTests {
  @Test func readsTopLevelStringsFromTheWholeText() {
    let scanner = scanned([tricky])
    #expect(scanner.values == trickyValues)
    #expect(
      scanner.keys == [
        "status", "lemma", "phonetic", "partOfSpeech", "definition", "otherSenses", "examples",
        "count", "flag", "empty", "contextTranslation",
      ])
  }

  @Test func everyTwoWaySplitGivesTheSameValues() {
    let count = tricky.unicodeScalars.count
    for cut in 0...count {
      #expect(scanned(pieces(tricky, at: [cut])).values == trickyValues, "cut at \(cut)")
    }
  }

  @Test func randomSplitsGiveTheSameValues() {
    var generator = SplitMix64(state: 42)
    let count = tricky.unicodeScalars.count
    for _ in 0..<300 {
      let cuts = (0..<Int.random(in: 1...40, using: &generator)).map { _ in
        Int.random(in: 0...count, using: &generator)
      }
      #expect(scanned(pieces(tricky, at: cuts)).values == trickyValues, "cuts \(cuts.sorted())")
    }
  }

  @Test func oneScalarAtATime() {
    let cuts = Array(1..<tricky.unicodeScalars.count)
    #expect(scanned(pieces(tricky, at: cuts)).values == trickyValues)
  }

  /// A field shows up only once its closing quote arrives, so a half-received escape or
  /// value never reaches the screen.
  @Test func aFieldAppearsOnlyWhenItsValueEnds() {
    var scanner = TopLevelFieldScanner()
    scanner.feed(#"{"status":"ok","definition":"经营一家\"#)
    #expect(scanner.values == ["status": "ok"])
    scanner.feed(#""店\""#)
    #expect(scanner.values["definition"] == nil)
    scanner.feed(#"","otherSenses":[{"definition":"x"}"#)
    #expect(scanner.values == ["status": "ok", "definition": #"经营一家"店""#])
  }

  @Test func ignoresTextAroundTheObjectAndTopLevelArrays() {
    #expect(scanned([#"["a","b"]"#]).values.isEmpty)
    #expect(scanned([#"noise "x" {"a":"1"} tail"#]).values == ["a": "1"])
  }

  @Test func aCardStreamedInPiecesGivesItsDefinitionBeforeTheEnd() throws {
    let json = cardJSON()
    let index = try #require(json.range(of: #""otherSenses""#)).lowerBound
    var scanner = TopLevelFieldScanner()
    scanner.feed(String(json[..<index]))
    #expect(scanner.values["definition"] == "经营")
    #expect(scanner.values["contextTranslation"] == "她经营一家面包店。")
    scanner.feed(String(json[index...]))
    #expect(scanner.values["level"] == "A2")
    #expect(scanner.values.count == 7)
  }
}
