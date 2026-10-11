// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
  import Foundation
  import Sparkle

  /// Debug only (`DICT_UPDATE_HEADLESS=1`): Sparkle's user interface replaced by a driver
  /// that agrees to everything, installs and relaunches, and logs each phase, so
  /// `scripts/update-test.sh` runs with no one at the Mac.
  @MainActor
  final class HeadlessUserDriver: NSObject, SPUUserDriver {
    private func phase(_ name: String) {
      Log.update.notice("headless: \(name, privacy: .public)")
    }

    func show(
      _ request: SPUUpdatePermissionRequest,
      reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
      phase("permission request")
      reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
      phase("checking")
    }

    func showUpdateFound(
      with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
      reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
      phase("found \(appcastItem.versionString)")
      reply(.install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
      phase("not found \((error as NSError).code)")
      acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
      let error = error as NSError
      phase("error \(error.domain) \(error.code)")
      acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
      phase("downloading")
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() {
      phase("extracting")
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
      phase("ready to install")
      reply(.install)
    }

    func showInstallingUpdate(
      withApplicationTerminated applicationTerminated: Bool,
      retryTerminatingApplication: @escaping () -> Void
    ) {
      phase("installing, terminated \(applicationTerminated)")
    }

    func showUpdateInstalledAndRelaunched(
      _ relaunched: Bool, acknowledgement: @escaping () -> Void
    ) {
      phase("installed, relaunched \(relaunched)")
      acknowledgement()
    }

    func dismissUpdateInstallation() {
      phase("dismissed")
    }
  }
#endif
