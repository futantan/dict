// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The `LICENSE` file that sits next to the database.
public func licenseNotice(_ manifest: Manifest) -> String {
  """
  dict-en-zh.sqlite — English to Simplified Chinese dictionary data for Dict
  Version \(manifest.snapshotDate)

  This database is licensed under the Creative Commons Attribution-ShareAlike 4.0
  International License (CC BY-SA 4.0):
  https://creativecommons.org/licenses/by-sa/4.0/
  Full legal code: https://creativecommons.org/licenses/by-sa/4.0/legalcode

  It is an adaptation of the following openly licensed works; their authors and the changes
  made are listed in ATTRIBUTION:
  \(manifest.sources.map { "- \($0.name) (\($0.license))" }.joined(separator: "\n"))

  Wiktionary text (Chinese and English editions) is dual-licensed under CC BY-SA and the
  GFDL; this adaptation uses it under CC BY-SA 4.0 only.

  If you share this database or anything adapted from it, you must give the same credit and
  license your adaptation under CC BY-SA 4.0 (or a compatible license).

  The data is provided as is, without warranties of any kind, express or implied, including
  without limitation warranties of title, merchantability, fitness for a particular purpose,
  non-infringement, accuracy, or the presence or absence of errors.

  The Dict application that reads this file is separate software under its own license
  (GPL-3.0-or-later); this license covers the dictionary data only.

  """
}

/// The `ATTRIBUTION` file: every source with its authors, license and link, plus what was
/// changed (CC BY-SA 4.0 section 3(a)).
public func attributionNotice(_ manifest: Manifest) -> String {
  var text = """
    dict-en-zh.sqlite — attribution
    Version \(manifest.snapshotDate)

    Changes made to the sources: English entries were selected from the Chinese Wiktionary
    extraction, the 英語 and 英语 sections were merged, and glosses were converted from
    Traditional to Simplified Chinese with ICU's Traditional-Simplified transform. From the
    English Wiktionary extraction, the Mandarin rows of each English entry's translation
    tables were taken as glosses (simplified form, one gloss per table) together with the
    table's English sense label. Wiki markup and extraction residue were removed, the senses
    of both editions were merged, reordered and deduplicated, parts of speech were mapped onto
    a fixed set, British and American IPA were separated, an inflection-to-lemma index was
    derived, and word frequencies were converted to Zipf values. Every sense records the
    edition it came from (`sense.source`, zh or en), and the `wiki_title` column of its
    headword names the page: https://<source>.wiktionary.org/wiki/<wiki_title>

    """
  for source in manifest.sources {
    text += """

      \(source.name)
      \((source.credit + [source.extraction].compactMap { $0 }).joined(separator: "\n"))
      Homepage: \(source.homepage)
      Snapshot: \(source.snapshotDate), \(source.url)
      License: \(source.license), \(source.licenseURL)

      """
  }
  return text
}

/// The `sources` value of the `meta` table: the manifest's inputs as JSON, keys sorted.
public func sourcesJSON(_ manifest: Manifest) throws -> String {
  struct Entry: Encodable {
    let name, url, snapshotDate, sha256, license, licenseURL: String
  }
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  let entries = manifest.sources.map {
    Entry(
      name: $0.name, url: $0.url, snapshotDate: $0.snapshotDate, sha256: $0.sha256,
      license: $0.license, licenseURL: $0.licenseURL)
  }
  return String(decoding: try encoder.encode(entries), as: UTF8.self)
}
