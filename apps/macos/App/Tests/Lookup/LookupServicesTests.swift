// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import Testing

@testable import DictApp

struct LookupServicesTests {
  @Test func theVocabularyLogLivesInAFolderNamedByTheBundleID() throws {
    let support = FileManager.default.temporaryDirectory
      .appendingPathComponent("dict-support-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: support) }

    let url = try vocabURL(applicationSupport: support, bundleID: "au.ibra.dict.dev")
    #expect(url == support.appendingPathComponent("au.ibra.dict.dev/vocab.sqlite"))
    var isFolder: ObjCBool = false
    #expect(
      FileManager.default.fileExists(
        atPath: url.deletingLastPathComponent().path, isDirectory: &isFolder))
    #expect(isFolder.boolValue)
    // An existing folder is fine.
    #expect(try vocabURL(applicationSupport: support, bundleID: "au.ibra.dict.dev") == url)
  }

  @Test func anAppWithoutTheDictionaryHasNoInstantLayer() {
    // The test bundle carries no dictionary resource.
    #expect(openBundledLexicon(Bundle(for: BundleMarker.self)) == nil)
  }

  @Test func everyCaptureSourceHasALogName() {
    let sources: [CaptureSource] = [.accessibility, .menuCopy, .keyCopy, .ocr, .typed]
    #expect(Set(sources.map(LookupSource.init)).count == sources.count)
  }

  @Test(arguments: [
    ("Learn", "要学"),
    ("Translate", "作为句子翻译"),
    ("Look Up", "查这个词"),
    ("Looked up %lld times", "第 %lld 次"),
    ("Nothing to look up", "没有可查的内容"),
  ])
  func theCardSpeaksChinese(key: String, expected: String) throws {
    let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    #expect(bundle.localizedString(forKey: key, value: "<missing>", table: "Card") == expected)
  }

  @Test func partsOfSpeechAreAbbreviated() {
    #expect(CardStrings.partOfSpeech("verb") == "v.")
    #expect(CardStrings.partOfSpeech("phrasal verb") == "phr. v.")
    #expect(CardStrings.partOfSpeech("idiom") == "idiom")
  }
}

private final class BundleMarker {}

@MainActor
struct PronunciationPaceTests {
  @Test func againRightAwayIsSlowThenNormal() {
    var pace = PronunciationPace()
    let start = ContinuousClock.now
    #expect(pace.next(at: start) == .normal)
    #expect(pace.next(at: start + .seconds(1)) == .slow)
    #expect(pace.next(at: start + .seconds(2)) == .normal)
  }

  @Test func afterAPauseItIsNormalAgain() {
    var pace = PronunciationPace()
    let start = ContinuousClock.now
    #expect(pace.next(at: start) == .normal)
    #expect(pace.next(at: start + .seconds(4)) == .normal)
  }
}
