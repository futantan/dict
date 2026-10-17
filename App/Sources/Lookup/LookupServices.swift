// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// The parts of the vocabulary log a session writes (architecture 8.1); `VocabStore`.
protocol SessionVocab: Sendable {
  func record(_ lookup: LookupRecord) async throws -> RecordedLookup
  func completeLookup(
    encounterID: Int64, card: StoredCard, sense: String?, sentenceTranslation: String?
  ) async throws
  func recordSentence(_ event: SentenceRecord) async throws
  func setTier(_ tier: Tier, termID: Int64, on day: LocalDay) async throws
}

extension VocabStore: SessionVocab {}

/// Where the vocabulary log lives: `<Application Support>/<bundle id>/vocab.sqlite`, one per
/// bundle id, so the Dev and Release apps keep separate logs (architecture 8.2). Creates the
/// folder when it is missing.
func vocabURL(applicationSupport: URL, bundleID: String) throws -> URL {
  let folder = applicationSupport.appendingPathComponent(bundleID, isDirectory: true)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  return folder.appendingPathComponent("vocab.sqlite")
}

/// The dictionary shipped in the app's resources (architecture 7.2), or nil, logged, when
/// the app was built without it or it cannot be opened: then there is no instant layer and
/// the card shows the model's part only.
func openBundledLexicon(_ bundle: Bundle = .main) -> Lexicon? {
  guard let url = bundle.url(forResource: "dict-en-zh", withExtension: "sqlite") else {
    Log.store.notice("no dictionary in the app bundle: cards come from the model only")
    return nil
  }
  do {
    return try Lexicon(url: url)
  } catch {
    Log.store.error("dictionary not usable: \(String(describing: error), privacy: .public)")
    return nil
  }
}

/// The capture source as the vocabulary log names it.
extension LookupSource {
  init(_ source: CaptureSource) {
    switch source {
    case .accessibility: self = .accessibility
    case .menuCopy: self = .menuCopy
    case .keyCopy: self = .keyCopy
    case .ocr: self = .ocr
    case .typed: self = .typed
    }
  }
}
