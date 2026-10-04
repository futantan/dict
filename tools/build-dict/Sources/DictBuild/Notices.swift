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

  It is an adaptation of Wiktionary content and other openly licensed data; the authors,
  sources and the changes made are listed in ATTRIBUTION. Wiktionary text is dual-licensed
  under CC BY-SA and the GFDL; this adaptation uses it under CC BY-SA 4.0 only.

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
    extraction, the 英語 and 英语 sections were merged, glosses were converted from Traditional
    to Simplified Chinese with ICU's Traditional-Simplified transform, wiki markup and
    extraction residue were removed, parts of speech were mapped onto a fixed set, British and
    American IPA were separated, an inflection-to-lemma index was derived, and word frequencies
    were converted to Zipf values. The `wiki_title` column of every headword names the
    Wiktionary page it was taken from: https://zh.wiktionary.org/wiki/<wiki_title>

    """
  for source in manifest.sources {
    text += """

      \(source.name)
      \(source.credit.joined(separator: "\n"))
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
