// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

/// The 5 ms budget of architecture 7.4 on the real database. Set `DICT_DB` to its path, e.g.
/// `DICT_DB=$PWD/build/dict/dict-en-zh.sqlite make test-core`; without it the test is skipped.
struct LexiconTimingTests {
  static let databasePath = ProcessInfo.processInfo.environment["DICT_DB"]
  static let skipNotice =
    "SKIPPED Lexicon 5 ms timing: set DICT_DB to the real dict-en-zh.sqlite to run it"

  /// Exact hits, forms, a very frequent word, a phrase, a miss, and words that reach the
  /// NLTagger step (`flurbing` and `xyzzies` are in no table).
  static let terms: [(String, String?)] = [
    ("ran", nil), ("running", nil), ("fine", nil), ("the", nil), ("went", nil),
    ("taken", nil), ("take off", nil), ("leaves", "The leaves fell."),
    ("flurbing", nil), ("xyzzies", "Two xyzzies sat there."),
  ]

  @Test(.enabled(if: databasePath != nil, Comment(rawValue: skipNotice)))
  func lookupsTakeUnderFiveMilliseconds() async throws {
    guard let path = Self.databasePath else { return }
    let lexicon = try Lexicon(url: URL(filePath: path))
    #expect(await !lexicon.lookup("ran", context: nil).isEmpty)
    for (term, context) in Self.terms {
      _ = await lexicon.lookup(term, context: context)
      var samples: [Duration] = []
      for _ in 0..<21 {
        let start = ContinuousClock.now
        _ = await lexicon.lookup(term, context: context)
        samples.append(ContinuousClock.now - start)
      }
      let median = samples.sorted()[samples.count / 2]
      let milliseconds =
        Double(median.components.seconds) * 1e3 + Double(median.components.attoseconds) / 1e15
      print("Lexicon timing: \(term) median \(String(format: "%.3f", milliseconds)) ms")
      #expect(median < .milliseconds(5), "\(term): median \(median)")
    }
  }
}
