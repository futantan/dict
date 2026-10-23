// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Sparkle

/// Sparkle's updater with the feed from `UpdateFeed` (Design/architecture.md 15.6).
/// It checks once a day by itself (Info.plist) and when the menu asks.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
  private let feed: URL
  private let headless: Bool
  private var updater: SPUUpdater?
  /// Kept here as well: the updater's reference is not documented as strong.
  private var userDriver: (any SPUUserDriver)?

  /// Starts the updater, or returns nil, logged, when updates are off for this build.
  static func start(
    bundle: Bundle = .main,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Updater? {
    if UpdateFeed.isTranslocated(bundle.bundleURL) {
      Log.update.notice("updates off: translocated; move the app to Applications")
      return nil
    }
    guard
      let feed = UpdateFeed.resolve(info: bundle.infoDictionary ?? [:], environment: environment)
    else {
      Log.update.info("updates off: no feed or public key for this build")
      return nil
    }
    let updater = Updater(feed: feed, headless: UpdateFeed.isHeadless(environment))
    return updater.start(bundle: bundle) ? updater : nil
  }

  private init(feed: URL, headless: Bool) {
    self.feed = feed
    self.headless = headless
  }

  private func start(bundle: Bundle) -> Bool {
    let driver = makeUserDriver(bundle: bundle)
    let updater = SPUUpdater(
      hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: self)
    do {
      try updater.start()
    } catch {
      Log.update.error("updater not started: \(String(describing: error), privacy: .public)")
      return false
    }
    self.updater = updater
    userDriver = driver
    Log.update.notice(
      "updater started: feed \(self.feed, privacy: .public), headless \(self.headless, privacy: .public)"
    )
    // The headless test run checks at once instead of waiting for the daily check.
    if headless { updater.checkForUpdates() }
    return true
  }

  private func makeUserDriver(bundle: Bundle) -> any SPUUserDriver {
    #if DEBUG
      if headless { return HeadlessUserDriver() }
    #endif
    return SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
  }

  var canCheckForUpdates: Bool { updater?.canCheckForUpdates ?? false }

  /// The menu's 「检查更新…」: Sparkle's windows say what it found, also when nothing.
  func checkForUpdates() {
    updater?.checkForUpdates()
  }

  // MARK: - SPUUpdaterDelegate

  func feedURLString(for updater: SPUUpdater) -> String? {
    feed.absoluteString
  }

  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    Log.update.notice("update found: \(item.versionString, privacy: .public)")
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
    Log.update.info("no update: \((error as NSError).code, privacy: .public)")
  }

  func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
    Log.update.notice("installing \(item.versionString, privacy: .public)")
  }

  func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
    Log.update.notice("relaunching")
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
    let error = error as NSError
    Log.update.error(
      "update aborted: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
  }
}
