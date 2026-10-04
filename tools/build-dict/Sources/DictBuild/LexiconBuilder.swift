// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The Wiktionary edition a sense comes from; stored as `sense.source` (`zh`, `en`) so every
/// sense can be credited to its page, `https://<source>.wiktionary.org/wiki/<wiki_title>`.
public enum Edition: String, Sendable, Hashable {
  /// Chinese Wiktionary: Chinese definitions of English words.
  case zh
  /// English Wiktionary: the Mandarin rows of an English word's translation tables.
  case en
}

/// One short definition: a part of speech from the model card's enum, a Simplified Chinese
/// gloss, the edition it came from and, for a translation table, the table's English sense
/// hint (`sense` table).
public struct Sense: Sendable, Hashable {
  public var pos: String
  public var gloss: String
  public var source: Edition
  public var hint: String?

  public init(pos: String, gloss: String, source: Edition = .zh, hint: String? = nil) {
    self.pos = pos
    self.gloss = gloss
    self.source = source
    self.hint = hint
  }
}

/// One dictionary entry (`headword` table, plus its senses).
public struct Headword: Sendable, Equatable {
  public var lemma: String
  public var key: String
  public var zipf: Double?
  public var ipaUK: String?
  public var ipaUS: String?
  public var wikiTitle: String
  public var senses: [Sense]
}

/// An inflected or alternative spelling that points at a headword (`form` table).
public struct FormLink: Sendable, Hashable, Comparable {
  public var formKey: String
  public var lemmaKey: String

  public init(formKey: String, lemmaKey: String) {
    self.formKey = formKey
    self.lemmaKey = lemmaKey
  }

  public static func < (a: FormLink, b: FormLink) -> Bool {
    (a.formKey, a.lemmaKey) < (b.formKey, b.lemmaKey)
  }
}

/// Everything that goes into the database, in insertion order: headwords sorted by key, forms
/// sorted by (form, lemma). Sorting here is what makes the output reproducible.
public struct Lexicon: Sendable, Equatable {
  public var headwords: [Headword]
  public var forms: [FormLink]
}

/// Merges wiktextract entries of both editions into headwords. Entries are added in file
/// order; the Chinese edition's two English headings (英語, 英语) simply feed the same
/// builder. Words whose keys collide (`Wiktionary`, `wiktionary`; `Turkey`, `turkey`) become
/// one headword. `build` orders each headword's senses (see `rank`).
public struct LexiconBuilder: Sendable {
  /// A sense before ordering: where it ranks and what it is.
  struct Candidate: Sendable {
    var sense: Sense
    var tier: Tier
    /// Number of languages in the sense's translation table (English edition), 0 otherwise.
    var languages: Int
    /// Order of arrival, the tie-breaker.
    var order: Int
  }

  /// Display tiers, first to last.
  enum Tier: Int, Sendable, Comparable {
    /// English Wiktionary translation tables of common nouns, verbs, adjectives and so on.
    case table
    /// Chinese Wiktionary definitions.
    case definition
    /// Chinese Wiktionary definitions that are rarely the meaning a reader wants first: a
    /// lone character from a list of near-synonyms (peaceful: 康, 宁, 泰), a surname, a
    /// place or a personal name.
    case demoted
    /// Proper-noun entries of either edition (Long the surname, Turkey the country).
    case name

    static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
  }

  private struct Group: Sendable {
    var spellings: [String] = []
    var candidates: [Candidate] = []
    var enIPA = IPAChoice()
    var zhIPA = IPAChoice()
  }

  private var groups: [String: Group] = [:]
  private var links: Set<FormLink> = []
  private var arrivals = 0

  public init() {}

  public mutating func add(_ entry: WiktionaryEntry, from edition: Edition = .zh) {
    guard entry.langCode == "en" else { return }
    let key = normalizedKey(entry.word)
    guard !key.isEmpty else { return }
    addLinks(entry, key: key)

    let pos = partOfSpeech(entry.pos, word: entry.word)
    let isName = entry.pos == "name"
    var candidates: [Candidate] = []
    switch edition {
    case .zh:
      for gloss in definitions(entry) {
        candidates.append(
          Candidate(
            sense: Sense(pos: pos, gloss: gloss), tier: isName ? .name : zhTier(gloss),
            languages: 0, order: nextArrival()))
      }
    case .en:
      for table in translationTables(entry) {
        candidates.append(
          Candidate(
            sense: Sense(pos: pos, gloss: table.gloss, source: .en, hint: table.hint),
            tier: isName ? .name : .table, languages: table.languages, order: nextArrival()))
      }
    }
    let sounds = entry.sounds ?? []
    // Most English Wiktionary entries have neither a Mandarin translation nor a pronunciation;
    // a group for each would hold a million words in memory for nothing.
    guard groups[key] != nil || !candidates.isEmpty || sounds.contains(where: { $0.ipa != nil })
    else { return }

    var group = groups[key, default: Group()]
    if !candidates.isEmpty, !group.spellings.contains(entry.word) {
      group.spellings.append(entry.word)
    }
    group.candidates += candidates
    switch edition {
    case .zh: group.zhIPA.add(sounds)
    case .en: group.enIPA.add(sounds)
    }
    groups[key] = group
  }

  /// Form-of senses and, for a base form, its inflection table. An abbreviation that expands
  /// to several words (HALT: hungry, angry, lonely, tired) is a spelling of none of them.
  private mutating func addLinks(_ entry: WiktionaryEntry, key: String) {
    for sense in entry.senses ?? [] {
      let tags = sense.tags ?? []
      let targets = (sense.formOf ?? []) + (sense.altOf ?? [])
      guard !tags.contains(where: marginalTags.contains),
        targets.count == 1 || !tags.contains(where: abbreviationTags.contains)
      else { continue }
      for target in targets { link(form: key, to: target.word) }
    }
    // The table of a comparative or superlative entry lists the whole paradigm, base form
    // included (`best`: good 原級, better), so only a base form's table gives its inflections.
    let forms = entry.forms ?? []
    guard !forms.contains(where: { isBaseFormOfAnother($0, word: entry.word) }) else { return }
    let words = entry.word.split(separator: " ").count
    for form in forms where isInflection(form) {
      // A spelling variant has as many words as the word itself; table residue such as
      // "usage notes" does not.
      let isSpelling = (form.tags ?? []).contains("alternative")
      guard !isSpelling || form.form.split(separator: " ").count == words else { continue }
      link(form: normalizedKey(form.form), to: entry.word)
    }
  }

  /// The finished lexicon. `zipf` gives each key's frequency. `blocklist` holds keys removed
  /// on request and `key<TAB>gloss` pairs that remove a single wrong gloss.
  ///
  /// - Headwords without a usable sense are dropped; their spelling may still resolve through
  ///   the form table.
  /// - A headword with only proper-noun senses is dropped when its key is also an inflection of
  ///   another headword: `was` is the past of `be`, not the surname Was.
  /// - A form link to a single-word lemma is dropped when the lemma is far rarer than the form
  ///   (more than 2 on the Zipf scale), which removes dialect lemmas such as `made` → Scots
  ///   `mak` but keeps Latin plurals (`algae` → `alga`, 1.7 apart). Multi-word lemmas
  ///   (`atm` → automatic teller machine) have no frequency and are always kept.
  public func build(zipf: (String) -> Double?, blocklist: Set<String> = []) -> Lexicon {
    var senses: [String: [Sense]] = [:]
    for (key, group) in groups where !blocklist.contains(key) {
      let kept = group.candidates.filter { !blocklist.contains("\(key)\t\($0.sense.gloss)") }
      let ranked = rank(kept)
      if !ranked.isEmpty { senses[key] = ranked }
    }
    let forms = links.filter { link in
      guard senses[link.lemmaKey] != nil, !blocklist.contains(link.formKey) else { return false }
      guard let formZipf = zipf(link.formKey), !link.lemmaKey.contains(" ") else { return true }
      return (zipf(link.lemmaKey) ?? 0) >= formZipf - 2
    }
    func onlyNames(_ key: String) -> Bool {
      groups[key]?.candidates.allSatisfy { $0.tier == .name } ?? true
    }
    // Forms of a common word; a form of another proper noun (France, Frances) does not count.
    let inflectedKeys = Set(forms.filter { !onlyNames($0.lemmaKey) }.map(\.formKey))

    var headwords: [Headword] = []
    for key in senses.keys.sorted() {
      guard let group = groups[key], let senses = senses[key] else { continue }
      if onlyNames(key) && inflectedKeys.contains(key) { continue }
      let lemma = displaySpelling(group.spellings, key: key)
      // English Wiktionary first: its pronunciation sections are the fuller and more
      // consistently labelled of the two.
      let ipa = (group.enIPA + group.zhIPA).result
      headwords.append(
        Headword(
          lemma: lemma, key: key, zipf: zipf(key), ipaUK: ipa.uk, ipaUS: ipa.us,
          wikiTitle: lemma, senses: senses))
    }
    let known = Set(headwords.map(\.key))
    return Lexicon(
      headwords: headwords, forms: forms.filter { known.contains($0.lemmaKey) }.sorted())
  }

  private mutating func link(form formKey: String, to lemma: String) {
    let lemmaKey = normalizedKey(lemma)
    guard isPlausibleForm(formKey), !lemmaKey.isEmpty, formKey != lemmaKey else { return }
    links.insert(FormLink(formKey: formKey, lemmaKey: lemmaKey))
  }

  private mutating func nextArrival() -> Int {
    arrivals += 1
    return arrivals
  }
}

/// The spelling a headword is shown with, among those of its entries that gave a sense: the
/// one with the fewest capitals (`Russia` over the pejorative `RuSSia`, `turkey` over
/// `Turkey`), ties broken alphabetically.
func displaySpelling(_ spellings: [String], key: String) -> String {
  spellings.min { a, b in
    let capitals = (a.count(where: \.isUppercase), b.count(where: \.isUppercase))
    return capitals.0 != capitals.1 ? capitals.0 < capitals.1 : a < b
  } ?? key
}

/// Orders one headword's senses and drops repeats.
///
/// 1. By tier: translation tables, then Chinese definitions, then demoted definitions, then
///    proper nouns.
/// 2. Translation tables by how many languages the table has, most first: Wiktionary editors
///    translate a word's central meaning into the most languages (`light`: electromagnetic
///    waves 264, of low weight 126, point of view 15). Everything else keeps page order.
/// 3. A sense is dropped when every one of its terms (split at 、，；) already appears in an
///    earlier sense, so 奔跑 after 跑、奔跑、走 and the second 银行 of `bank` go. Glosses are
///    compared after Traditional-Simplified conversion, which happened when they were read.
func rank(_ candidates: [LexiconBuilder.Candidate]) -> [Sense] {
  let ordered = candidates.sorted {
    ($0.tier, -$0.languages, $0.order) < ($1.tier, -$1.languages, $1.order)
  }
  var seen: Set<String> = []
  var senses: [Sense] = []
  for candidate in ordered {
    let terms = glossTerms(candidate.sense.gloss)
    guard !terms.isSubset(of: seen) else { continue }
    seen.formUnion(terms)
    senses.append(candidate.sense)
  }
  return senses
}

func glossTerms(_ gloss: String) -> Set<String> {
  Set(
    gloss.split(whereSeparator: { "、，；,;".contains($0) })
      .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
}

/// The tier of a Chinese Wiktionary definition from a common (not proper-noun) entry.
func zhTier(_ gloss: String) -> LexiconBuilder.Tier {
  let isLoneCharacter = gloss.count == 1 && containsHan(gloss)
  let isName = ["姓氏", "地名", "人名"].contains(where: gloss.contains)
  return isLoneCharacter || isName ? .demoted : .definition
}

/// One translation table of an English Wiktionary entry, reduced to its Mandarin row.
struct TranslationTable: Equatable {
  /// The table's sense hint, nil when the page has a single untitled table.
  var hint: String?
  /// Mandarin translations in Simplified Chinese, joined with 、.
  var gloss: String
  /// Distinct languages the table translates into, Mandarin included.
  var languages: Int
}

/// Regroups an entry's translations by table (the row's `sense` hint), wherever the
/// extraction attached them, keeping the order in which tables first appear. Tables without
/// a usable Mandarin row are left out.
func translationTables(_ entry: WiktionaryEntry) -> [TranslationTable] {
  let rows = (entry.senses ?? []).flatMap { $0.translations ?? [] } + (entry.translations ?? [])
  var hints: [String] = []
  var languages: [String: Set<String>] = [:]
  var words: [String: [String]] = [:]
  var regionalWords: [String: [String]] = [:]
  for row in rows {
    let hint = row.sense?.trimmingCharacters(in: .whitespaces) ?? ""
    if languages[hint] == nil { hints.append(hint) }
    languages[hint, default: []].insert(row.langCode ?? row.lang ?? "")
    guard isMandarin(row) else { continue }
    let tags = row.tags ?? []
    if tags.contains(where: marginalTags.contains) { continue }
    if tags.contains(where: regionalTags.contains) {
      regionalWords[hint, default: []] += mandarinWords(row.word ?? "")
    } else {
      words[hint, default: []] += mandarinWords(row.word ?? "")
    }
  }
  return hints.compactMap { hint in
    var unique: [String] = []
    for word in words[hint, default: []] + regionalWords[hint, default: []]
    where !unique.contains(word) {
      unique.append(word)
    }
    guard !unique.isEmpty else { return nil }
    return TranslationTable(
      hint: hint.isEmpty ? nil : hint, gloss: unique.joined(separator: "、"),
      languages: languages[hint]?.count ?? 0)
  }
}

/// Mandarin rows: `lang` "Chinese Mandarin" (coded `cmn` or `zh`), not Cantonese, Hokkien,
/// Dungan and the other Chinese languages.
func isMandarin(_ row: WiktionaryEntry.Translation) -> Bool {
  row.lang?.hasPrefix("Chinese Mandarin") == true || row.langCode == "cmn"
}

/// Words outside mainland usage or everyday register; they go after the table's other words
/// (計程車 after 出租车 for taxi).
let regionalTags: Set = [
  "Taiwan", "Hong-Kong", "Macau", "Singapore", "Malaysia", "literary", "dated", "uncommon",
  "historical", "Catholic", "Protestant",
]

/// The Simplified Chinese words of one table cell. A cell is `traditional /simplified` when the
/// two differ (`銀行 /银行`), and may hold alternatives joined by `&` with ASCII-parenthesized
/// qualifiers or romanizations (`彈 /弹&(formal)彈奏 /弹奏` gives 弹, 弹奏). Words without a
/// Chinese character (`OK`) and editor notes (`but see 美國 /美国`) are left out.
func mandarinWords(_ cell: String) -> [String] {
  // Leaked wiki markup ({{t+|…}}, [[…]]) means the cell was not parsed.
  guard !["{{", "}}", "[[", "]]"].contains(where: cell.contains) else { return [] }
  // Most cells are plain words; the regular expressions are slow enough to skip for them.
  let unqualified = cell.contains("(") ? cell.replacing(/\([^()]*\)/, with: "") : cell
  if unqualified.contains(where: { $0.isASCII && $0.isLowercase }),
    unqualified.firstMatch(of: /(^|\s)[a-z][a-z.:]*(\s|$)/) != nil
  {
    return []
  }
  return unqualified.split(separator: "&").compactMap { alternative in
    let simplified = alternative.split(separator: " /").last.map(String.init) ?? ""
    let word = toSimplified(simplified).trimmingCharacters(in: .whitespaces)
    return containsHan(word) ? word : nil
  }
}

/// Labels of usages too marginal to point a lookup at or to show as a translation.
let marginalTags: Set = [
  "obsolete", "archaic", "dialectal", "nonstandard", "misspelling", "clipping", "rare",
]

/// The cleaned Chinese definitions of a Chinese Wiktionary entry, in page order. Pointer
/// senses (form-of, alt-of) and placeholders (no-gloss) are not definitions.
func definitions(_ entry: WiktionaryEntry) -> [String] {
  (entry.senses ?? []).compactMap { sense in
    let tags = sense.tags ?? []
    guard ((sense.formOf ?? []) + (sense.altOf ?? [])).isEmpty,
      !tags.contains(where: ["no-gloss", "form-of", "alt-of"].contains)
    else { return nil }
    return senseGloss(sense.glosses ?? [])
  }
}

/// A sense's `glosses` is a chain from the broadest parent gloss to the sense itself; the most
/// specific part that survives cleaning is the definition.
func senseGloss(_ glosses: [String]) -> String? {
  glosses.reversed().lazy.compactMap(cleanGloss).first
}

/// Inflections (plural, past, participles, third person, comparison) and alternative
/// spellings, as `tags` or as free-text labels such as 簡單過去時. Marginal forms (obsolete
/// `yode`, nonstandard `goed`) are left out, and so are alternative spellings with any label
/// beyond a national standard (Scots `girl` for grill, Northumbrian `gan` for go).
func isInflection(_ form: WiktionaryEntry.Form) -> Bool {
  let tags = form.tags ?? []
  if tags.contains(where: marginalTags.contains) { return false }
  if tags.contains("alternative") {
    return tags.allSatisfy { $0 == "alternative" || spellingStandards.contains($0) }
  }
  if tags.contains(where: inflectionTags.contains) { return true }
  return (form.rawTags ?? []).contains { raw in
    let label = toSimplified(raw)
    return inflectionLabels.contains(where: label.contains)
  }
}

/// A form labelled as the positive (base) degree that is not the entry's own word.
func isBaseFormOfAnother(_ form: WiktionaryEntry.Form, word: String) -> Bool {
  guard normalizedKey(form.form) != normalizedKey(word) else { return false }
  return (form.tags ?? []).contains("positive")
    || (form.rawTags ?? []).contains { toSimplified($0).contains("原级") }
}

private let inflectionTags: Set = [
  "plural", "past", "participle", "third-person", "comparative", "superlative",
]
private let spellingStandards: Set = [
  "US", "UK", "British", "American", "Canada", "Commonwealth", "Ireland", "Australia",
  "New-Zealand", "South-Africa", "India",
]
private let abbreviationTags: Set = ["abbreviation", "acronym", "initialism"]
private let inflectionLabels = ["过去", "复数", "分词", "第三人称", "比较级", "最高级"]

/// Rejects table residue and analytic comparatives ("more happy"); a form needs a letter.
func isPlausibleForm(_ key: String) -> Bool {
  guard key.contains(where: \.isLetter), !key.hasPrefix("more "), !key.hasPrefix("most ")
  else { return false }
  return !key.contains(where: { "()[]{}<>|=/".contains($0) })
}
