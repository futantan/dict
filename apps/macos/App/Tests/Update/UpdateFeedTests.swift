// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictApp

struct UpdateFeedTests {
  /// 32 bytes, base64: the shape of `generate_keys`' public key.
  static let key = Data(repeating: 7, count: 32).base64EncodedString()
  static let feed = "https://github.com/tantan/dict/releases/latest/download/appcast.xml"
  static let local = "http://127.0.0.1:8770/appcast.xml"

  static func info(feed: String = feed, key: String = key) -> [String: Any] {
    [UpdateFeed.feedKey: feed, UpdateFeed.publicKeyKey: key]
  }

  // MARK: Release

  @Test func releaseUsesTheInfoPlistFeed() {
    let url = UpdateFeed.resolve(info: Self.info(), environment: [:], debug: false)

    #expect(url?.absoluteString == Self.feed)
  }

  @Test func releaseIgnoresTheLocalOverride() {
    let url = UpdateFeed.resolve(
      info: Self.info(), environment: [UpdateFeed.feedVariable: Self.local], debug: false)

    #expect(url?.absoluteString == Self.feed)
  }

  @Test(arguments: [
    "",
    "https://github.com/OWNER/dict/releases/latest/download/appcast.xml",
    "http://example.com/appcast.xml",
    "https:///appcast.xml",
    "not a url",
  ])
  func releaseRefusesAnUnsetOrUnsafeFeed(feed: String) {
    #expect(UpdateFeed.resolve(info: Self.info(feed: feed), environment: [:], debug: false) == nil)
  }

  @Test func releaseRefusesAMissingFeedKey() {
    let info: [String: Any] = [UpdateFeed.publicKeyKey: Self.key]

    #expect(UpdateFeed.resolve(info: info, environment: [:], debug: false) == nil)
  }

  @Test(arguments: ["", "not base64!", Data(repeating: 1, count: 31).base64EncodedString()])
  func refusesAPublicKeyThatIsNotThirtyTwoBytes(key: String) {
    let info = Self.info(key: key)
    let local = [UpdateFeed.feedVariable: Self.local]

    #expect(UpdateFeed.resolve(info: info, environment: [:], debug: false) == nil)
    #expect(UpdateFeed.resolve(info: info, environment: local, debug: true) == nil)
  }

  // MARK: Debug

  @Test func debugIgnoresTheInfoPlistFeed() {
    #expect(UpdateFeed.resolve(info: Self.info(), environment: [:], debug: true) == nil)
  }

  @Test(arguments: [
    "http://127.0.0.1:8770/appcast.xml",
    "http://127.0.0.1/appcast.xml",
    " http://127.0.0.1:8770/appcast.xml\n",
  ])
  func debugUsesALocalOverride(value: String) {
    let url = UpdateFeed.resolve(
      info: Self.info(), environment: [UpdateFeed.feedVariable: value], debug: true)

    #expect(url?.host() == "127.0.0.1")
    #expect(url?.scheme == "http")
  }

  @Test(arguments: [
    "https://github.com/tantan/dict/releases/latest/download/appcast.xml",
    "http://localhost:8770/appcast.xml",
    "http://192.168.1.2:8770/appcast.xml",
    "http://127.0.0.1.example.com/appcast.xml",
    "https://127.0.0.1:8770/appcast.xml",
    "file:///tmp/appcast.xml",
    "",
  ])
  func debugRefusesAnythingButLocalHTTP(value: String) {
    let url = UpdateFeed.resolve(
      info: Self.info(), environment: [UpdateFeed.feedVariable: value], debug: true)

    #expect(url == nil)
  }

  // MARK: Headless and translocation

  @Test func headlessOnlyInDebugWithTheVariableSetToOne() {
    let on = [UpdateFeed.headlessVariable: "1"]

    #expect(UpdateFeed.isHeadless(on, debug: true))
    #expect(!UpdateFeed.isHeadless(on, debug: false))
    #expect(!UpdateFeed.isHeadless([UpdateFeed.headlessVariable: "0"], debug: true))
    #expect(!UpdateFeed.isHeadless([:], debug: true))
  }

  @Test func detectsATranslocatedBundle() {
    let translocated = URL(
      fileURLWithPath:
        "/private/var/folders/xy/abc/T/AppTranslocation/1A2B3C/d/Dict.app")

    #expect(UpdateFeed.isTranslocated(translocated))
    #expect(!UpdateFeed.isTranslocated(URL(fileURLWithPath: "/Applications/Dict.app")))
    #expect(!UpdateFeed.isTranslocated(URL(fileURLWithPath: "/Users/me/Downloads/Dict.app")))
  }

  // MARK: The built Info.plist

  /// The test host is the Debug app: no feed, and Sparkle's settings set so it never asks.
  @Test func debugInfoPlistHasNoFeedAndSparkleSettings() throws {
    let info = try #require(Bundle.main.infoDictionary)

    #expect(info[UpdateFeed.feedKey] as? String == "")
    #expect(info["SUFeedURL"] == nil)
    #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
    #expect(info["SUEnableSystemProfiling"] as? Bool == false)
    #expect(info["SUScheduledCheckInterval"] as? Int == 86400)
    #expect(UpdateFeed.resolve(info: info, environment: [:], debug: true) == nil)
  }
}
