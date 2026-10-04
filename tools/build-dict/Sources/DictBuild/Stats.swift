// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import NaturalLanguage

/// Coverage of the most frequent FrequencyWords tokens, for `build-dict stats`.
/// A token counts as covered when it is a headword or a form that points at one (what the
/// app's lookup does before lemmatizing); the second figure also lets `NLTagger(.lemma)`
/// reduce the token first, which is the app's last step (architecture 7.4).
/// Tokens without a letter (numbers, `'s` fragments) are skipped.
public func coverageReport(database: URL, frequencies: FrequencyTable, tops: [Int]) throws
  -> [String]
{
  let db = try SQLiteConnection(path: database.path, readOnly: true)
  let headwords = Set(try db.prepare("SELECT lemma_key FROM headword").rows().compactMap { $0[0] })
  let forms = Set(try db.prepare("SELECT form_key FROM form").rows().compactMap { $0[0] })
  let known = headwords.union(forms)

  let tagger = NLTagger(tagSchemes: [.lemma])
  func lemma(_ word: String) -> String? {
    tagger.string = word
    let tag = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma).0
    return tag.map { normalizedKey($0.rawValue) }
  }

  let tokens = frequencies.ranked.filter { $0.contains(where: \.isLetter) && !$0.hasPrefix("'") }
  let lemmas = tokens.prefix(tops.max() ?? 0).map { lemma($0) ?? $0 }
  return tops.map { top in
    let slice = tokens.prefix(top)
    let direct = slice.count { known.contains($0) }
    let withTagger = zip(slice, lemmas).count { token, lemma in
      known.contains(token) || known.contains(lemma)
    }
    // Distinct lemmas (NLTagger's lemma, else the token), each a headword or a form.
    let distinct = Set(lemmas.prefix(top))
    let lemmaHits = distinct.count { known.contains($0) }
    return "top \(top): tokens direct \(percent(direct, of: slice.count)), "
      + "with NLTagger \(percent(withTagger, of: slice.count)) of \(slice.count); "
      + "distinct lemmas \(percent(lemmaHits, of: distinct.count)) of \(distinct.count)"
  }
}

/// Times exact and form lookups the way the app would run them, on one connection: the first
/// query after opening (cold) and the mean over many repeated queries (hot).
public func timingReport(database: URL, exact: [String], forms: [String]) throws -> [String] {
  let exactSQL = """
    SELECT h.lemma, h.ipa_us, h.ipa_uk, h.zipf, s.pos, s.gloss FROM headword h
    JOIN sense s ON s.headword_id = h.id WHERE h.lemma_key = ? ORDER BY s.ord
    """
  let formSQL = """
    SELECT h.lemma, h.ipa_us, h.ipa_uk, h.zipf, s.pos, s.gloss FROM form f
    JOIN headword h ON h.id = f.headword_id JOIN sense s ON s.headword_id = h.id
    WHERE f.form_key = ? ORDER BY h.zipf DESC, s.ord
    """
  func measure(_ body: () throws -> Void) rethrows -> Double {
    let start = ContinuousClock.now
    try body()
    let elapsed = ContinuousClock.now - start
    return Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1e3
  }

  var lines: [String] = []
  for (label, sql, words) in [("exact", exactSQL, exact), ("form", formSQL, forms)] {
    guard let first = words.first else { continue }
    var statement: SQLiteConnection.Statement?
    var connection: SQLiteConnection?
    let cold = try measure {
      connection = try SQLiteConnection(path: database.path, readOnly: true)
      statement = try connection?.prepare(sql)
      _ = try statement?.rows([.text(first)])
    }
    let rounds = 20
    let hot = try measure {
      for _ in 0..<rounds { for word in words { _ = try statement?.rows([.text(word)]) } }
    }
    lines.append(
      String(
        format: "%@ lookup: cold %.3f ms (open + prepare + first query), hot %.4f ms per query",
        label, cold, hot / Double(rounds * words.count)))
  }
  return lines
}
