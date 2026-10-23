// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import DictCore

struct AppIdentityTests {
  @Test func readsAllFieldsFromInfoDictionary() throws {
    let identity = try #require(
      AppIdentity(infoDictionary: [
        "CFBundleName": "Sample",
        "CFBundleIdentifier": "org.example.sample",
        "CFBundleShortVersionString": "1.2.0",
        "CFBundleVersion": "42",
      ]))

    #expect(identity.name == "Sample")
    #expect(identity.bundleIdentifier == "org.example.sample")
    #expect(identity.version == "1.2.0")
    #expect(identity.build == "42")
    #expect(identity.versionDescription == "1.2.0 (42)")
  }

  @Test func prefersDisplayNameOverBundleName() throws {
    let identity = try #require(
      AppIdentity(infoDictionary: [
        "CFBundleDisplayName": "Sample Dev",
        "CFBundleName": "Sample_Dev",
        "CFBundleIdentifier": "org.example.sample.dev",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
      ]))

    #expect(identity.name == "Sample Dev")
  }

  @Test func missingRequiredKeysYieldNil() {
    #expect(AppIdentity(infoDictionary: [:]) == nil)
    #expect(
      AppIdentity(infoDictionary: [
        "CFBundleName": "Sample",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
      ]) == nil)
  }

  @Test func emptyStringsCountAsMissing() {
    #expect(
      AppIdentity(infoDictionary: [
        "CFBundleName": "",
        "CFBundleIdentifier": "org.example.sample",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
      ]) == nil)
  }
}
