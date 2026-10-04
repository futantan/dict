// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import NaturalLanguage

/// Named figures of a built database, in a fixed order, for `build-dict stats` and for the
/// before/after comparison of `build-dict update`.
public typealias Metrics = [(name: String, value: String)]

/// Table sizes, IPA coverage and coverage of the most frequent FrequencyWords tokens.
/// A token counts as covered when it is a headword or a form that points at one (what the
/// app's lookup does before lemmatizing); the second figure also lets `NLTagger(.lemma)`
/// reduce the token first, which is the app's last step (architecture 7.4).
/// Tokens without a letter (numbers, `'s` fragments) are skipped.
public func databaseMetrics(database: URL, frequencies: FrequencyTable, tops: [Int]) throws
  -> Metrics
{
  let db = try SQLiteConnection(path: database.path, readOnly: true)
  func count(_ sql: String) throws -> String {
    try db.prepare(sql).rows().first?.first.flatMap { $0 } ?? "0"
  }
  var metrics: Metrics = [
    ("headwords", try count("SELECT count(*) FROM headword")),
    ("senses", try count("SELECT count(*) FROM sense")),
  ]
  // Databases before schema 2 have no `source` column.
  if let rows = try? db.prepare("SELECT source, count(*) FROM sense GROUP BY source").rows() {
    metrics += rows.map { ("senses from \($0[0] ?? "")", $0[1] ?? "0") }
  }
  metrics += [
    ("forms", try count("SELECT count(*) FROM form")),
    ("ipa_uk", try count("SELECT count(*) FROM headword WHERE ipa_uk IS NOT NULL")),
    ("ipa_us", try count("SELECT count(*) FROM headword WHERE ipa_us IS NOT NULL")),
    (
      "ipa_uk of zipf >= 4.5",
      try count(
        """
        SELECT printf('%.1f%%', 100.0 * sum(ipa_uk IS NOT NULL) / count(*)) FROM headword
        WHERE zipf >= 4.5
        """)
    ),
  ]

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
  for top in tops {
    let slice = tokens.prefix(top)
    let direct = slice.count { known.contains($0) }
    let withTagger = zip(slice, lemmas).count { token, lemma in
      known.contains(token) || known.contains(lemma)
    }
    // Distinct lemmas (NLTagger's lemma, else the token), each a headword or a form.
    let distinct = Set(lemmas.prefix(top))
    let lemmaHits = distinct.count { known.contains($0) }
    metrics += [
      ("top \(top) tokens direct", percent(direct, of: slice.count)),
      ("top \(top) tokens with NLTagger", percent(withTagger, of: slice.count)),
      ("top \(top) distinct lemmas (\(distinct.count))", percent(lemmaHits, of: distinct.count)),
    ]
  }
  return metrics
}

/// The query behind architecture 7.4 steps 2 and 3: the term's own headword and every lemma
/// it is a form of, in display order. Ordered by frequency (`saw` → see before saw the tool,
/// `found` → find before found), except that an own headword without a translation table of
/// its own goes last: such an entry is first of all an inflection (`miles` → mile, `taken` →
/// take, `points` → point). On equal frequency the lemma goes first.
public let lookupSQL = """
  SELECT h.id, h.lemma FROM headword h
  WHERE h.lemma_key = ?1 OR h.id IN (SELECT headword_id FROM form WHERE form_key = ?1)
  ORDER BY
    h.lemma_key = ?1
      AND NOT EXISTS (SELECT 1 FROM sense WHERE headword_id = h.id AND source = 'en'),
    h.zipf IS NULL, h.zipf DESC, h.lemma_key = ?1, h.lemma_key
  """

/// The headwords the app shows for a term (`lookupSQL`), each with its first senses.
public func lookup(_ term: String, database: URL, senses: Int = 3) throws -> [(
  lemma: String, glosses: [String]
)] {
  let db = try SQLiteConnection(path: database.path, readOnly: true)
  let glosses = try db.prepare("SELECT gloss FROM sense WHERE headword_id = ? ORDER BY ord LIMIT ?")
  return try db.prepare(lookupSQL).rows([.text(normalizedKey(term))]).compactMap { row in
    guard let id = row[0].flatMap({ Int($0) }), let lemma = row[1] else { return nil }
    return (lemma, try glosses.rows([.integer(id), .integer(senses)]).compactMap { $0[0] })
  }
}

/// Lines comparing two sets of metrics by name; `before` may be empty.
public func comparisonLines(before: Metrics, after: Metrics) -> [String] {
  let previous = Dictionary(before.map { ($0.name, $0.value) }, uniquingKeysWith: { a, _ in a })
  return after.map { name, value in
    "\(name): \(previous[name] ?? "—") → \(value)"
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
