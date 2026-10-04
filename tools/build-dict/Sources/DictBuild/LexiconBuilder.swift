// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One short definition: a part of speech from the model card's enum and a Simplified Chinese
/// gloss (`sense` table).
public struct Sense: Sendable, Hashable {
  public var pos: String
  public var gloss: String

  public init(pos: String, gloss: String) {
    self.pos = pos
    self.gloss = gloss
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

/// Merges wiktextract entries into headwords. Entries are added in file order; the zh edition's
/// two English headings (英語, 英语) simply feed the same builder. Words whose keys collide
/// (`Wiktionary`, `wiktionary`; `Turkey`, `turkey`) become one headword, with proper-noun
/// senses after the others.
public struct LexiconBuilder: Sendable {
  private struct Group: Sendable {
    var spellings: [String] = []
    var senses: [Sense] = []
    var nameSenses: [Sense] = []
    var sounds: [Sound] = []
  }

  private var groups: [String: Group] = [:]
  private var links: Set<FormLink> = []

  public init() {}

  public mutating func add(_ entry: WiktionaryEntry) {
    guard entry.langCode == "en" else { return }
    let key = normalizedKey(entry.word)
    guard !key.isEmpty else { return }
    let pos = partOfSpeech(entry.pos, word: entry.word)

    var group = groups[key, default: Group()]
    if !group.spellings.contains(entry.word) { group.spellings.append(entry.word) }
    group.sounds += (entry.sounds ?? []).filter { $0.ipa != nil }
    for sense in entry.senses ?? [] {
      let targets = (sense.formOf ?? []) + (sense.altOf ?? [])
      if !targets.isEmpty {
        for target in targets { link(form: key, to: target.word) }
        continue
      }
      let tags = sense.tags ?? []
      if tags.contains("no-gloss") || tags.contains("form-of") || tags.contains("alt-of") {
        continue
      }
      guard let gloss = senseGloss(sense.glosses ?? []) else { continue }
      let candidate = Sense(pos: pos, gloss: gloss)
      if entry.pos == "name" {
        if !group.nameSenses.contains(candidate) { group.nameSenses.append(candidate) }
      } else if !group.senses.contains(candidate) {
        group.senses.append(candidate)
      }
    }
    groups[key] = group

    // The table of a comparative or superlative entry lists the whole paradigm, base form
    // included (`best`: good 原級, better), so only a base form's table gives its inflections.
    let forms = entry.forms ?? []
    guard !forms.contains(where: { isBaseFormOfAnother($0, word: entry.word) }) else { return }
    for form in forms where isInflection(form) {
      link(form: normalizedKey(form.form), to: entry.word)
    }
  }

  /// The finished lexicon. `zipf` gives each key's frequency and `blocklist` holds keys removed
  /// on request.
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
    let candidates = groups.filter {
      !blocklist.contains($0.key) && !($0.value.senses.isEmpty && $0.value.nameSenses.isEmpty)
    }
    let forms = links.filter { link in
      guard candidates[link.lemmaKey] != nil, !blocklist.contains(link.formKey) else {
        return false
      }
      guard let formZipf = zipf(link.formKey), !link.lemmaKey.contains(" ") else { return true }
      return (zipf(link.lemmaKey) ?? 0) >= formZipf - 2
    }
    let inflectedKeys = Set(forms.map(\.formKey))

    var headwords: [Headword] = []
    for key in candidates.keys.sorted() {
      guard let group = candidates[key] else { continue }
      if group.senses.isEmpty && inflectedKeys.contains(key) { continue }
      let lemma = group.spellings.contains(key) ? key : group.spellings.min() ?? key
      let ipa = pickIPA(group.sounds)
      headwords.append(
        Headword(
          lemma: lemma, key: key, zipf: zipf(key), ipaUK: ipa.uk, ipaUS: ipa.us,
          wikiTitle: lemma, senses: group.senses + group.nameSenses))
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
}

/// A sense's `glosses` is a chain from the broadest parent gloss to the sense itself; the most
/// specific part that survives cleaning is the definition.
func senseGloss(_ glosses: [String]) -> String? {
  glosses.reversed().lazy.compactMap(cleanGloss).first
}

/// Inflections (plural, past, participles, third person, comparison) and alternative
/// spellings, as `tags` or as free-text labels such as 簡單過去時.
func isInflection(_ form: WiktionaryEntry.Form) -> Bool {
  if let tags = form.tags, tags.contains(where: inflectionTags.contains) { return true }
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
  "plural", "past", "participle", "third-person", "comparative", "superlative", "alternative",
]
private let inflectionLabels = ["过去", "复数", "分词", "第三人称", "比较级", "最高级"]

/// Rejects table residue and analytic comparatives ("more happy"); a form needs a letter.
func isPlausibleForm(_ key: String) -> Bool {
  guard key.contains(where: \.isLetter), !key.hasPrefix("more "), !key.hasPrefix("most ")
  else { return false }
  return !key.contains(where: { "()[]{}<>|=/".contains($0) })
}
