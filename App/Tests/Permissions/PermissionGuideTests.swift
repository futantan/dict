// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictApp

struct PermissionGuideTests {
  private let granted = PermissionStatus(accessibility: true, postEvent: true)
  private let none = PermissionStatus(accessibility: false, postEvent: false)
  private let onlyAccessibility = PermissionStatus(accessibility: true, postEvent: false)

  // MARK: - Status

  @Test func missingListsWhatIsOff() {
    #expect(granted.missing.isEmpty)
    #expect(none.missing == [.accessibility, .postEvent])
    #expect(onlyAccessibility.missing == [.postEvent])
  }

  @Test func newlyGrantedComparesWithThePreviousRead() {
    #expect(granted.newlyGranted(since: none) == [.accessibility, .postEvent])
    #expect(onlyAccessibility.newlyGranted(since: none) == [.accessibility])
    #expect(none.newlyGranted(since: granted).isEmpty)
    #expect(granted.newlyGranted(since: granted).isEmpty)
  }

  // MARK: - Failures to issues

  @Test func captureFailuresMapToIssues() {
    let cases: [(CaptureFailure, PermissionStatus, PermissionIssue?)] = [
      (.noAccessibilityPermission, none, .missing(.accessibility)),
      // Trusted, yet the accessibility API refused: the grant belongs to an old signature.
      (.noAccessibilityPermission, granted, .staleAccessibility),
      (.noAccessibilityPermission, onlyAccessibility, .staleAccessibility),
      (.noPostEventPermission, none, .missing(.accessibility)),
      (.noPostEventPermission, onlyAccessibility, .missing(.postEvent)),
      // Granted since the capture ran: nothing to explain, just try again.
      (.noPostEventPermission, granted, nil),
      (.secureField, none, nil),
      (.clipboardDenied, none, nil),
      (.unreadable(axError: -25211), none, nil),
    ]
    for (failure, status, issue) in cases {
      #expect(PermissionIssue(failure, status: status) == issue, "\(failure) \(status)")
    }
  }

  @Test func replaceFailuresMapToIssues() {
    #expect(
      PermissionIssue(FailReason.noPostEventPermission, status: none) == .missing(.accessibility))
    #expect(
      PermissionIssue(FailReason.noPostEventPermission, status: onlyAccessibility)
        == .missing(.postEvent))
    #expect(PermissionIssue(FailReason.noPostEventPermission, status: granted) == nil)
    #expect(PermissionIssue(FailReason.pasteNotApplied, status: none) == nil)
    #expect(PermissionIssue(FailReason.clipboardDenied, status: none) == nil)
  }

  // MARK: - Notices

  private let app = PermissionGuide.AppIdentity(name: "Dict Dev", bundleID: "au.ibra.dict.dev")

  @Test func everyIssueOffersSystemSettings() {
    for issue in PermissionIssue.allCases {
      let notice = PermissionGuide.notice(for: issue, app: app)
      #expect(notice.title.isEmpty == false)
      #expect(notice.message?.contains("Dict Dev") == true, "\(issue)")
      let open = notice.actions.last
      #expect(open?.id == PermissionGuide.ActionID.openSettings)
      #expect(open?.isDefault == true)
      #expect(notice.actions.filter(\.isDefault).count == 1)
    }
  }

  @Test func issuesHaveDistinctTitlesOrMessages() {
    let notices = PermissionIssue.allCases.map { PermissionGuide.notice(for: $0, app: app) }
    #expect(Set(notices.map { "\($0.title)|\($0.message ?? "")" }).count == notices.count)
  }

  @Test func staleGrantExplainsTheResetCommand() {
    let notice = PermissionGuide.notice(for: .staleAccessibility, app: app)
    #expect(notice.message?.contains("tccutil reset Accessibility au.ibra.dict.dev") == true)
    #expect(
      notice.actions.map(\.id) == [
        PermissionGuide.ActionID.copyResetCommand, PermissionGuide.ActionID.openSettings,
      ])
    #expect(PermissionGuide.resetCommand(app) == "tccutil reset Accessibility au.ibra.dict.dev")
  }

  @Test func settingsURLOpensThePrivacyAccessibilityPane() {
    #expect(
      PermissionGuide.settingsURL.absoluteString
        == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
  }

  // MARK: - Actions

  @MainActor @Test func actionsOpenSettingsOrCopyTheCommand() {
    var opened: [URL] = []
    var copied: [String] = []
    let guide = PermissionGuide(
      app: app, openURL: { opened.append($0) }, copy: { copied.append($0) })

    #expect(guide.perform(PermissionGuide.ActionID.openSettings))
    #expect(opened == [PermissionGuide.settingsURL])
    #expect(guide.perform(PermissionGuide.ActionID.copyResetCommand))
    #expect(copied == ["tccutil reset Accessibility au.ibra.dict.dev"])
    #expect(guide.perform("retry") == false)
    #expect(opened.count == 1)
    #expect(copied.count == 1)
  }

  // MARK: - Chinese

  private func chinese(_ key: String) throws -> String {
    let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    return bundle.localizedString(forKey: key, value: "<missing>", table: "Permissions")
  }

  @Test func titlesHaveChineseTranslations() throws {
    #expect(try chinese("Accessibility permission needed") == "需要辅助功能权限")
    #expect(try chinese("Open System Settings") == "打开系统设置")
  }

  @Test func chineseMessageKeepsTheAppName() throws {
    let template = try chinese(
      "%@ needs Accessibility permission to read the text you select. Turn on %@ in System "
        + "Settings → Privacy & Security → Accessibility.")
    let message = String(format: template, "Dict Dev", "Dict Dev")
    #expect(message.contains("Dict Dev"))
    #expect(message.contains("辅助功能"))
  }
}
